#!/usr/bin/env python3
"""Exercise malformed storage schemas through the native CLI, without network I/O.

Mutations use this repository's Apache-2.0 real-complex-compatible fixture.
The compiler layout is retained; wrappers are minimal, handwritten envelopes.
"""

from copy import deepcopy
import json
from pathlib import Path
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def wrap(layout, wrapper, transient, abi=None):
    artifact = {'abi': [] if abi is None else abi, 'storageLayout': layout}
    if transient:
        artifact['storageLayout'] = {'storage': [], 'types': {}}
        artifact['transientStorageLayout'] = layout
    contracts = {'src/ComplexLayout.sol': {'ComplexLayout': artifact}}
    if wrapper == 'standard':
        return {'contracts': contracts}
    if wrapper == 'hardhat':
        return {'output': {'contracts': contracts}}
    return artifact


def check_abi_handlers(binary, old_path, new_path):
    """Validate special-function mutability, including valid controls."""
    checks = 0
    for wrapper in ('flat', 'standard', 'hardhat'):
        root = '$'
        if wrapper != 'flat':
            root += '.output' if wrapper == 'hardhat' else ''
            root += '.contracts["src/ComplexLayout.sol"]["ComplexLayout"]'
        for kind in ('receive', 'fallback'):
            for mutability in ('pure', 'view', 'nonpayable', 'payable'):
                valid = mutability == 'payable' or (kind == 'fallback' and mutability == 'nonpayable')
                empty = {'storage': [], 'types': {}}
                artifact = wrap(empty, wrapper, False, [{'type': kind, 'stateMutability': mutability}])
                control = wrap(empty, wrapper, False)
                for sides in (('old', 'new'),) if valid else (('old',), ('new',), ('old', 'new')):
                    old_path.write_text(json.dumps(artifact if 'old' in sides else control))
                    new_path.write_text(json.dumps(artifact if 'new' in sides else control))
                    for command in ('check', 'abi'):
                        for output_format in ('text', 'json'):
                            args = [str(binary), command, str(old_path), str(new_path), '--format', output_format]
                            result = subprocess.run(args, capture_output=True, check=False)
                            repeat = subprocess.run(args, capture_output=True, check=False)
                            context = (wrapper, kind, mutability, sides, command, output_format)
                            assert result.returncode == repeat.returncode == (0 if valid else 2), context
                            assert result.stdout == repeat.stdout, context
                            if output_format == 'json':
                                findings = json.loads(result.stdout)
                                if valid:
                                    assert findings == [], context
                                else:
                                    assert len(findings) == len(sides), context
                                    assert {item.get('input') for item in findings} == set(sides), context
                                    for item in findings:
                                        assert item['code'] == 'artifact.field.invalid', context
                                        assert item['severity'] == 'error', context
                                        assert item['location']['path'] == root + '.abi[0].stateMutability', context
                            elif valid:
                                assert result.stdout == b'', context
                            else:
                                assert b'artifact.field.invalid' in result.stdout, context
                                assert b'.abi[0].stateMutability' in result.stdout, context
                            checks += 1
    return checks


def check_abi_widths(binary, old_path, new_path):
    """Reject noncanonical widths wherever ABI parameters are decoded."""
    checks = 0
    for wrapper in ('flat', 'standard', 'hardhat'):
        root = '$'
        if wrapper != 'flat':
            root += '.output' if wrapper == 'hardhat' else ''
            root += '.contracts["src/ComplexLayout.sol"]["ComplexLayout"]'
        for bad_type, good_type in (('uint0256', 'uint256'), ('int08', 'int8'), ('bytes01', 'bytes1')):
            for position in ('input', 'output', 'tuple', 'event', 'error'):
                documents = []
                for type_name in (good_type, bad_type):
                    param = {'type': type_name}
                    entry = {'type': 'function', 'name': 'f', 'inputs': [], 'outputs': [], 'stateMutability': 'view'}
                    location = '.abi[0].inputs[0].type'
                    if position == 'output':
                        entry['outputs'] = [param]
                        location = '.abi[0].outputs[0].type'
                    elif position == 'tuple':
                        entry['inputs'] = [{'type': 'tuple[]', 'components': [param]}]
                        location = '.abi[0].inputs[0].components[0].type'
                    elif position == 'event':
                        entry = {'type': 'event', 'name': 'Changed', 'anonymous': False, 'inputs': [{**param, 'indexed': False}]}
                    elif position == 'error':
                        entry = {'type': 'error', 'name': 'Bad', 'inputs': [param]}
                    else:
                        entry['inputs'] = [param]
                    documents.append(wrap({'storage': [], 'types': {}}, wrapper, False, [entry]))
                valid, invalid = documents
                for sides in ((), ('old',), ('new',), ('old', 'new')):
                    old_path.write_text(json.dumps(invalid if 'old' in sides else valid))
                    new_path.write_text(json.dumps(invalid if 'new' in sides else valid))
                    for command in ('check', 'abi'):
                        args = [str(binary), command, str(old_path), str(new_path), '--format', 'json']
                        result = subprocess.run(args, capture_output=True, check=False)
                        repeat = subprocess.run(args, capture_output=True, check=False)
                        context = (wrapper, bad_type, position, sides, command)
                        assert result.returncode == repeat.returncode == (2 if sides else 0), context
                        assert result.stdout == repeat.stdout, context
                        findings = json.loads(result.stdout)
                        assert len(findings) == len(sides), context
                        assert {item.get('input') for item in findings} == set(sides), context
                        for item in findings:
                            assert item['code'] == 'artifact.field.invalid', context
                            assert item['severity'] == 'error', context
                            assert item['location']['path'] == root + location, context
                        checks += 1
    return checks


def expected_path(path, code, wrapper, transient):
    suffix = path[0]
    for key in path[1:]:
        if isinstance(key, int):
            suffix += f'[{key}]'
        elif suffix == 'types':
            suffix += f'[{json.dumps(key)}]'
        else:
            suffix += '.' + key
    if code != 'artifact.field.invalid':
        return ('transientStorage.' if transient else '') + suffix
    root = '$'
    if wrapper != 'flat':
        root += '.output' if wrapper == 'hardhat' else ''
        root += '.contracts["src/ComplexLayout.sol"]["ComplexLayout"]'
    return root + ('.transientStorageLayout.' if transient else '.storageLayout.') + suffix


def main():
    binary = Path(sys.argv[1]).resolve()
    source = json.loads(
        (ROOT / 'fixtures/real-complex-compatible/old.json').read_text()
    )
    layout = source['contracts']['src/ComplexLayout.sol']['ComplexLayout']['storageLayout']
    types = layout['types']
    mapping = next(key for key, value in types.items() if value['encoding'] == 'mapping')
    struct = next(key for key, value in types.items() if 'members' in value)
    array = next(key for key, value in types.items() if 'base' in value)
    # Add a dynamic array to exercise both array encodings with the same base.
    types['t_dynamic'] = {
        'encoding': 'dynamic_array', 'label': 'uint256[]',
        'numberOfBytes': '32', 'base': 't_uint256',
    }
    types['t_struct_array'] = {
        'encoding': 'inplace', 'label': types[struct]['label'] + '[2]',
        'numberOfBytes': str(int(types[struct]['numberOfBytes']) * 2),
        'base': struct,
    }
    mutations = []
    for field in ('label', 'slot', 'offset', 'type'):
        mutations.append((['storage', 0, field], 'storage.entry.field.missing', None))
        mutations.append((['types', struct, 'members', 0, field], 'storage.entry.field.missing', None))
    for type_id, field in (
        (mapping, 'key'), (mapping, 'value'), (struct, 'members'),
        (array, 'base'), ('t_dynamic', 'base'),
        ('t_struct_array', 'base'),
        ('t_uint256', 'label'), ('t_uint256', 'encoding'),
        ('t_uint256', 'numberOfBytes'),
    ):
        mutations.append((['types', type_id, field], 'storage.type.field.missing', None))
    for type_id, field in ((mapping, 'key'), (mapping, 'value'), (array, 'base'), ('t_dynamic', 'base')):
        mutations.append((['types', type_id, field], 'storage.type.reference.missing', 't_missing'))
    mutations.extend([
        (['types', array, 'members'], 'storage.type.shape.invalid', []),
        (['types', 't_dynamic', 'members'], 'storage.type.shape.invalid', []),
        (['storage', 0, 'type'], 'storage.entry.type.missing', 't_missing'),
        (['types', 't_uint256', 'encoding'], 'storage.type.encoding.unsupported', 'unknown'),
        (['types', struct, 'members'], 'artifact.field.invalid', {}),
        (['storage', 0, 'offset'], 'artifact.field.invalid', '0'),
    ])
    checks = 0
    with tempfile.TemporaryDirectory() as directory:
        old_path = Path(directory) / 'old.json'
        new_path = Path(directory) / 'new.json'
        for wrapper in ('flat', 'standard', 'hardhat'):
            for transient in (False, True):
                valid = wrap(layout, wrapper, transient)
                old_path.write_text(json.dumps(valid))
                new_path.write_text(json.dumps(valid))
                for command in ('check', 'storage'):
                    result = subprocess.run(
                        [str(binary), command, str(old_path), str(new_path), '--format', 'json'],
                        capture_output=True, check=False,
                    )
                    assert result.returncode == 0 and json.loads(result.stdout) == [], (wrapper, transient, command)
                    checks += 1
        for path, code, replacement in mutations:
            damaged = deepcopy(layout)
            parent = damaged
            for key in path[:-1]:
                parent = parent[key]
            if replacement is None:
                del parent[path[-1]]
            else:
                parent[path[-1]] = replacement
            for wrapper in ('flat', 'standard', 'hardhat'):
                for transient in (False, True):
                    valid = wrap(layout, wrapper, transient)
                    invalid = wrap(damaged, wrapper, transient)
                    for sides in (('old',), ('new',), ('old', 'new')):
                        old_path.write_text(json.dumps(invalid if 'old' in sides else valid))
                        new_path.write_text(json.dumps(invalid if 'new' in sides else valid))
                        for command in ('check', 'storage'):
                            args = [str(binary), command, str(old_path), str(new_path), '--format', 'json']
                            result = subprocess.run(args, capture_output=True, check=False)
                            repeat = subprocess.run(args, capture_output=True, check=False)
                            context = (path, code, wrapper, transient, sides, command)
                            assert result.returncode == repeat.returncode == 2, context
                            assert result.stdout == repeat.stdout, context
                            findings = json.loads(result.stdout)
                            assert findings, context
                            assert {item.get('input') for item in findings} == set(sides), context
                            assert all(item['severity'] == 'error' for item in findings), context
                            assert not any(item['code'].endswith(('.changed', '.added', '.removed')) for item in findings), context
                            for side in sides:
                                matching = [item for item in findings if item['code'] == code and item['input'] == side]
                                assert matching, context
                                location = expected_path(path, code, wrapper, transient)
                                assert any(item['location']['path'] == location for item in matching), context
                            checks += 1
        checks += check_abi_handlers(binary, old_path, new_path)
        checks += check_abi_widths(binary, old_path, new_path)
    print(f'input integrity: {checks} checks passed')


if __name__ == '__main__':
    main()
