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


def wrap(layout, wrapper, transient):
    artifact = {'abi': [], 'storageLayout': layout}
    if transient:
        artifact['storageLayout'] = {'storage': [], 'types': {}}
        artifact['transientStorageLayout'] = layout
    contracts = {'src/ComplexLayout.sol': {'ComplexLayout': artifact}}
    if wrapper == 'standard':
        return {'contracts': contracts}
    if wrapper == 'hardhat':
        return {'output': {'contracts': contracts}}
    return artifact


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
    print(f'input integrity: {checks} checks passed')


if __name__ == '__main__':
    main()
