#!/usr/bin/env python3
"""Regression contract: preserve the homelab rules, including repeated names.

Run: python3 -m unittest discover -s scripts/tests -p 'test_vm_rules.py'
Requires PyYAML and Helm. Set HELM to test a specific Helm binary.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[2]
CHART = ROOT / 'charts/vm-rules'
HELM = os.environ.get('HELM', 'helm')


def render(values=None, release='test', files=(), expect_success=True):
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / 'values.yaml'
        path.write_text(yaml.safe_dump(values or {}))
        args = [HELM, 'template', release, str(CHART), '--namespace', 'monitoring']
        for file in files:
            args.extend(['-f', str(CHART / file)])
        args.extend(['-f', str(path)])
        result = subprocess.run(args, text=True, capture_output=True)
    if not expect_success:
        if result.returncode == 0:
            raise AssertionError('invalid configuration rendered successfully')
        return result.stderr
    if result.returncode:
        raise AssertionError(result.stderr)
    return [d for d in yaml.safe_load_all(result.stdout) if d]


class RuleContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.baseline = json.loads((Path(__file__).parent / 'fixtures/vm-rules/baseline.json').read_text())
        cls.platform = render(release='platform-rules', files=['examples/platform-values.yaml'])
        cls.temporal = render(release='temporal-rules', files=['examples/temporal-values.yaml'])

    def test_full_homelab_parity(self):
        actual = {}
        for doc in self.platform + self.temporal:
            self.assertEqual(doc['kind'], 'VMRule')
            self.assertEqual(doc['apiVersion'], 'operator.victoriametrics.com/v1beta1')
            meta = doc['metadata']
            key = (meta['namespace'], meta['annotations']['charts.duynhlab.dev/source-name'])
            self.assertNotIn(key, actual)
            actual[key] = doc
        expected = {(d['metadata']['namespace'], d['metadata']['name']): d for d in self.baseline}
        self.assertEqual(actual.keys(), expected.keys())
        for key, before in expected.items():
            with self.subTest(resource=key):
                after = actual[key]
                self.assertEqual(after['spec'], before['spec'])
                for field in ('labels', 'annotations'):
                    for name, value in before['metadata'].get(field, {}).items():
                        self.assertEqual(after['metadata'][field][name], value)
        rules = [r for d in actual.values() for g in d['spec']['groups'] for r in g['rules']]
        self.assertEqual(len(actual), 71)
        self.assertEqual(sum('alert' in r for r in rules), 255)
        self.assertEqual(sum('record' in r for r in rules), 60)

    def test_bundles_opt_in_and_legacy_switch(self):
        self.assertEqual(len(render()), 5)
        self.assertEqual(render({'defaultRules': {'enabled': False}}), [])
        defaults = yaml.safe_load((CHART / 'values.yaml').read_text())
        for bundle in defaults['bundles']:
            with self.subTest(bundle=bundle):
                docs = render({'defaultRules': {'enabled': False}, 'bundles': {bundle: {'enabled': True}}})
                self.assertGreater(len(docs), 0)
                expected = len(list((CHART / 'bundles' / bundle).glob('*.yaml')))
                self.assertEqual(len(docs), expected)

    def test_extra_rules_are_data_not_templates(self):
        groups = [{'name': 'custom', 'interval': '30s', 'rules': [
            {'alert': 'Custom', 'expr': 'vector(1)', 'for': '1m',
             'annotations': {'description': '{{ $labels.pod }} {{ .Values.secret }}'},
             'labels': {'severity': 'warning'}},
            {'record': 'custom:record', 'expr': 'vector(2)'}]}]
        docs = render({'defaultRules': {'enabled': False}, 'extraRules': {'custom': {
            'groups': groups, 'namespace': 'custom', 'labels': {'team': 'platform'}}}})
        self.assertEqual(docs[0]['spec']['groups'], groups)
        self.assertEqual(docs[0]['metadata']['namespace'], 'custom')
        self.assertEqual(docs[0]['metadata']['labels']['team'], 'platform')

    def test_cnpg_can_target_another_cluster(self):
        docs = render({'defaultRules': {'enabled': False}, 'cnpg': {'clusters': {
            'analytics-db': {'namespace': 'analytics', 'haExcludedJob': 'analytics/dr'}}}})
        self.assertEqual(len(docs), 15)
        text = json.dumps(docs)
        self.assertNotIn('@@CNPG_', text)
        self.assertNotIn('product-db', text)
        self.assertTrue(all(d['metadata']['namespace'] == 'analytics' for d in docs))
        ha = [r for d in docs for g in d['spec']['groups'] for r in g['rules']
              if r.get('alert') in ('CNPGClusterHAWarning', 'CNPGClusterHACritical')]
        self.assertEqual(len(ha), 2)
        self.assertTrue(all('job!="analytics/dr"' in r['expr'] for r in ha))

    def test_operator_is_singleton(self):
        docs = render({'defaultRules': {'enabled': False}, 'cnpg': {'operator': {
            'enabled': True, 'namespace': 'operators'}}})
        self.assertEqual(len(docs), 1)
        self.assertEqual(docs[0]['metadata']['namespace'], 'operators')
        self.assertEqual(len(docs[0]['spec']['groups'][0]['rules']), 2)

    def test_job_remap_does_not_modify_homelab(self):
        changed = render({'jobNames': {'kubelet': 'wrong', 'node-exporter': 'wrong'}},
                         release='platform-rules', files=['examples/platform-values.yaml'])
        self.assertEqual(changed, self.platform)

    def test_invalid_configuration_fails(self):
        cases = [
            ({'bundles': {'typo': {'enabled': True}}}, 'typo'),
            ({'cnpg': {'clusters': {'test': {}}}}, 'namespace'),
            ({'extraRules': {'bad': {'groups': []}}}, 'groups'),
            ({'rules': {'certmanager': {'file': 'missing.yml'}}}, 'missing or empty'),
            ({'extraRules': {'kubernetes': {'groups': [{'name': 'x', 'rules': [
                {'alert': 'X', 'expr': 'vector(0)'}]}]}}}, 'duplicate VMRule'),
            ({'defaultRules': {'enabled': False}, 'bundles': {'watchdog': {'enabled': True}},
              'extraRules': {'watchdog': {'groups': [{'name': 'x', 'rules': [
                  {'alert': 'X', 'expr': 'vector(0)'}]}]}}}, 'duplicate VMRule'),
        ]
        for values, message in cases:
            with self.subTest(values=values):
                self.assertIn(message, render(values, expect_success=False))


if __name__ == '__main__':
    unittest.main()
