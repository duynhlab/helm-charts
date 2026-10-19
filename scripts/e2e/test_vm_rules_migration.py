#!/usr/bin/env python3
"""Exercise converter -> native VMRule cutover in a dedicated Kind cluster.

Requires PyYAML, Helm, kubectl, the VM operator 0.68.1 and Prometheus CRDs.
KUBECONFIG must point to the disposable kind-vm-rules-migration context.
No external notifier is configured. Workloads/rules are retained for inspection;
remove the disposable cluster after the test. Output evidence lives outside Git.
"""
import argparse
import collections
import json
import os
from pathlib import Path
import subprocess
import time
import urllib.parse

import yaml

ROOT = Path(__file__).resolve().parents[2]
CHART = ROOT / 'charts/vm-rules'
LABEL = 'rules.duynhlab.dev/source'
NS = 'monitoring'
EVIDENCE = {}


def run(*args, data=None):
    result = subprocess.run(args, input=data, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f'{args}: {result.stderr}')
    return result.stdout


def kubectl(*args, data=None):
    return run('kubectl', *args, data=data)


def apply(docs):
    kubectl('apply', '-f', '-', data=yaml.safe_dump_all(docs, sort_keys=False))


def wait_for(description, check, timeout=240):
    deadline = time.monotonic() + timeout
    last_error = ''
    while time.monotonic() < deadline:
        try:
            value = check()
            if value:
                print(f'PASS: {description}', flush=True)
                return value
        except (RuntimeError, AssertionError, KeyError) as exc:
            last_error = str(exc)
        time.sleep(2)
    raise AssertionError(f'Timed out: {description}: {last_error}')


def api(service, port, path):
    return json.loads(kubectl('get', '--raw',
        f'/api/v1/namespaces/{NS}/services/{service}:{port}/proxy{path}'))


def rules():
    return api('vmalert-migration', 8080, '/api/v1/rules')['data']['groups']


def identity(groups):
    return collections.Counter(json.dumps(
        [g['name'], g['interval'], r['name'], r['query'], r['type'], r.get('labels', {}),
         r.get('duration'), r.get('annotations', {})], sort_keys=True)
        for g in groups for r in g['rules'] if r['name'] != 'MigrationOwnershipSentinel')


def snapshot(phase, expected):
    def ready():
        groups = rules()
        current = [r for g in groups for r in g['rules']]
        if len(current) != expected or any(r.get('health') != 'ok' for r in current):
            return False
        return groups
    groups = wait_for(f'{phase}: {expected} rules loaded, all health=ok', ready)
    EVIDENCE[phase] = {
        'groups': len(groups), 'rules': sum(len(g['rules']) for g in groups),
        'states': dict(collections.Counter(r.get('state', r['type']) for g in groups for r in g['rules'])),
        'sentinel': [r for g in groups for r in g['rules'] if r['name'] == 'MigrationSloSentinel'],
    }
    return groups


def select(exclude):
    patch = {'spec': {'ruleNamespaceSelector': {}, 'ruleSelector': {'matchExpressions': [
        {'key': LABEL, 'operator': 'NotIn', 'values': [exclude]}]}}}
    kubectl('-n', NS, 'patch', 'vmalert', 'migration', '--type=merge', '-p', json.dumps(patch))


def ownership_query():
    return [r['query'] for g in rules() for r in g['rules'] if r['name'] == 'MigrationOwnershipSentinel']


def objects(kind, label):
    return json.loads(kubectl('get', kind, '-A', '-l', label, '-o', 'json'))['items']


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--evidence', required=True, type=Path)
    args = parser.parse_args()
    if not os.environ.get('KUBECONFIG') or kubectl('config', 'current-context').strip() != 'kind-vm-rules-migration':
        raise SystemExit('Use the dedicated kind-vm-rules-migration KUBECONFIG only')
    baseline = json.loads((ROOT / 'scripts/tests/fixtures/vm-rules/baseline.json').read_text())
    total = sum(len(g['rules']) for d in baseline for g in d['spec']['groups']) + 4
    for doc in baseline:
        doc['metadata'].setdefault('labels', {})[LABEL] = 'manifests'
    apply([{'apiVersion': 'v1', 'kind': 'Namespace', 'metadata': {'name': ns}}
           for ns in (NS, 'product', 'platform', 'cloudnative-pg')])
    apply(baseline)
    apply([{'apiVersion': 'monitoring.coreos.com/v1', 'kind': 'PrometheusRule',
            'metadata': {'name': 'ownership-old', 'namespace': NS, 'labels': {LABEL: 'manifests'}},
            'spec': {'groups': [{'name': 'ownership', 'interval': '5s', 'rules': [
                {'alert': 'MigrationOwnershipSentinel', 'expr': 'vector(1)'}]}]}}])
    apply([
        {'apiVersion': 'operator.victoriametrics.com/v1beta1', 'kind': 'VMSingle',
         'metadata': {'name': 'migration', 'namespace': NS},
         'spec': {'retentionPeriod': '1', 'storage': {'resources': {'requests': {'storage': '1Gi'}}}}},
        {'apiVersion': 'operator.victoriametrics.com/v1beta1', 'kind': 'VMAlertmanager',
         'metadata': {'name': 'migration', 'namespace': NS},
         'spec': {'replicaCount': 1, 'configRawYaml': 'route:\n  receiver: discard\nreceivers:\n  - name: discard\n'}},
        {'apiVersion': 'operator.victoriametrics.com/v1beta1', 'kind': 'VMAlert',
         'metadata': {'name': 'migration', 'namespace': NS},
         'spec': {'evaluationInterval': '5s',
                  'datasource': {'url': 'http://vmsingle-migration.monitoring.svc:8428'},
                  'remoteWrite': {'url': 'http://vmsingle-migration.monitoring.svc:8428'},
                  'remoteRead': {'url': 'http://vmsingle-migration.monitoring.svc:8428'},
                  'notifier': {'url': 'http://vmalertmanager-migration.monitoring.svc:9093'},
                  'ruleNamespaceSelector': {}, 'ruleSelector': {'matchExpressions': [
                      {'key': LABEL, 'operator': 'NotIn', 'values': ['chart']}]}}},
        # An unlabelled stand-in for separately owned Sloth output must survive every phase.
        {'apiVersion': 'monitoring.coreos.com/v1', 'kind': 'PrometheusRule',
         'metadata': {'name': 'slo-sentinel', 'namespace': NS},
         'spec': {'groups': [{'name': 'slo-sentinel', 'interval': '5s', 'rules': [
             {'alert': 'MigrationSloSentinel', 'expr': 'vector(1)', 'for': '2m', 'labels': {'severity': 'info'}},
             {'record': 'migration:constant', 'expr': 'vector(7)'},
             {'alert': 'MigrationRecordingSentinel', 'expr': 'migration:constant == 7'}]}]}}
    ])
    wait_for('all old rules converted with migration label',
             lambda: len(objects('vmrule', f'{LABEL}=manifests')) == len(baseline) + 1)
    before = snapshot('baseline', total)
    for release, values in [('platform-rules', 'platform-values.yaml'), ('temporal-rules', 'temporal-values.yaml')]:
        run('helm', 'upgrade', '--install', release, str(CHART), '-n', NS,
            '-f', str(CHART / 'examples' / values), '--wait', '--timeout', '180s')
    native = [d for d in objects('vmrule', f'{LABEL}=chart') if d['metadata']['name'] != 'ownership-new']
    assert len(native) == len(baseline)
    expected = {(d['metadata']['namespace'], d['metadata']['name']): d['spec'] for d in baseline}
    actual = {(d['metadata']['namespace'], d['metadata']['annotations']['charts.duynhlab.dev/source-name']): d['spec'] for d in native}
    assert actual == expected, 'API-server round-trip changed the rule specs'
    apply([{'apiVersion': 'operator.victoriametrics.com/v1beta1', 'kind': 'VMRule',
            'metadata': {'name': 'ownership-new', 'namespace': NS, 'labels': {LABEL: 'chart'}},
            'spec': {'groups': [{'name': 'ownership', 'interval': '5s', 'rules': [
                {'alert': 'MigrationOwnershipSentinel', 'expr': 'vector(2)'}]}]}}])
    staged = snapshot('staged', total)
    assert identity(staged) == identity(before), 'Staging changed the evaluated rule set'
    select('manifests')
    # Operator v0.75 combines rules into one file. A canary proves source selection
    # even when the two production sets have identical content and file paths.
    wait_for('VMAlert selects native rules', lambda: ownership_query() == ['vector(2)'])
    after = snapshot('cutover', total)
    assert identity(after) == identity(before), 'Cutover changed the rule set'
    # Exercise rollback before deleting the old sources.
    select('chart')
    wait_for('rollback selects converted rules', lambda: ownership_query() == ['vector(1)'])
    assert identity(snapshot('rollback', total)) == identity(before)
    select('manifests')
    wait_for('cutover restored', lambda: ownership_query() == ['vector(2)'])
    kubectl('delete', 'prometheusrule', '-A', '-l', f'{LABEL}=manifests', '--wait=true')
    wait_for('converted old rules garbage-collected', lambda: not objects('vmrule', f'{LABEL}=manifests'))
    kubectl('-n', NS, 'patch', 'vmalert', 'migration', '--type=merge', '-p', json.dumps({
        'spec': {'selectAllByDefault': True, 'ruleSelector': None, 'ruleNamespaceSelector': None}}))
    assert identity(snapshot('cleanup', total)) == identity(before)
    wait_for('unlabelled SLO sentinel and recording consumer fire', lambda: all(
        any(r['name'] == name and r.get('state') == 'firing' for g in rules() for r in g['rules'])
        for name in ('MigrationSloSentinel', 'MigrationRecordingSentinel')))
    query = urllib.parse.urlencode({'query': 'migration:constant'})
    result = api('vmsingle-migration', 8428, '/api/v1/query?' + query)['data']['result']
    assert result and all(float(r['value'][1]) == 7 for r in result)
    EVIDENCE['recordingValue'] = 7
    EVIDENCE['kubernetes'] = json.loads(kubectl('version', '-o', 'json'))['serverVersion']['gitVersion']
    EVIDENCE['note'] = 'Disposable Kind: configuration/evaluation/cutover gate, not a replay of production metrics'
    args.evidence.write_text(json.dumps(EVIDENCE, indent=2) + '\n')
    print(f'PASS: migration, rollback, GC and recording checks; evidence: {args.evidence}')


if __name__ == '__main__':
    main()
