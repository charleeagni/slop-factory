import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../Sources/SlopFactory/XWebPoster.swift', import.meta.url), 'utf8');
const match = source.match(/private static let hasPostFailure = """\n([\s\S]*?)\n    """/);
assert.ok(match, 'post failure check must return a bounded result');
const script = match[1];
for (const [text, expected] of [[null, false], ['', false], ['  \n ', false], ['Could not post as @fixture_owner', true]]) {
  const result = vm.runInNewContext(script, {
    document: { querySelector: () => text === null ? null : { innerText: text } },
  });
  assert.equal(result, expected, 'only a nonempty alert is a definite post failure');
  assert.equal(typeof result, 'boolean', 'account text must not cross the JavaScript bridge');
}
console.log('Posting alert checks passed without exporting account text.');
