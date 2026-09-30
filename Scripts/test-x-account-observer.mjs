import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../Sources/FactoryCore/XAccountObservationScript.swift', import.meta.url), 'utf8');
const script = source.match(/public static let source = #"""\n([\s\S]*?)\n    """#/)[1];
function fixture({ href = '/Owner_123', url = 'https://x.com/home', subframe = false, dedicated = true, enabled = true } = {}) {
  const messages = [];
  const contexts = [];
  let mutation, poll, timeout;
  const state = { href, dedicated, reads: 0 };
  const window = { webkit: { messageHandlers: { slopXAccount: { postMessage(body) { const { generation, session, ...observation } = JSON.parse(JSON.stringify(body)); messages.push(observation); contexts.push({ generation, session }); } } } } };
  window.top = subframe ? {} : window;
  if (enabled) window.__slopXAccountContext = { generation: "generation-1", session: "session-1" };
  const environment = {
    window, location: new URL(url), URL,
    document: { documentElement: {}, querySelector(selector) {
      state.reads += 1;
      return selector === 'a[data-testid="AppTabBar_Profile_Link"]' && state.dedicated && state.href !== null
        ? { getAttribute: () => state.href } : null;
    } },
    MutationObserver: class { constructor(callback) { mutation = callback; } observe() {} disconnect() { mutation = undefined; } },
    setInterval(callback, delay) { assert.equal(delay, 2000); poll = callback; return 2; },
    clearInterval() { poll = undefined; },
    setTimeout(callback, delay) { assert.equal(delay, 400); timeout = callback; return 1; },
    clearTimeout() { timeout = undefined; },
  };
  vm.createContext(environment);
  vm.runInContext(script, environment);
  return { messages, contexts, state, queuedCallbacks() { return [mutation, poll, timeout].filter(Boolean); }, start() { window.__slopXAccountContext = { generation: "generation-2", session: "session-1" }; vm.runInContext(script, environment); }, stop() { window.__slopXAccountObserver?.stop(); }, mutate() { mutation?.(); }, flush() { timeout?.(); timeout = undefined; }, poll() { poll?.(); } };
}

const disabled = fixture({ enabled: false });
assert.equal(disabled.state.reads, 0, 'disabled scripts never read the account DOM');
assert.equal(disabled.messages.length, 0);

const signedIn = fixture();
assert.deepEqual(signedIn.contexts[0], { generation: 'generation-1', session: 'session-1' }, 'messages identify their choice and owning window');
assert.equal(signedIn.messages[0]?.handle, 'owner_123');
assert.equal(signedIn.messages[0]?.href, 'https://x.com/Owner_123');
for (const url of ['https://x.com/', 'https://x.com/compose/post']) {
  const existingSession = fixture({ url, href: '/ExistingOwner' });
  assert.deepEqual(existingSession.messages, [{ handle: 'existingowner', href: 'https://x.com/ExistingOwner' }],
    'opening the login or posting page captures an existing session without waiting for a DOM change');
}
const switchedAccount = fixture({ href: '/OwnerA' });
switchedAccount.state.href = null;
switchedAccount.mutate();
switchedAccount.flush();
switchedAccount.state.href = '/OwnerB';
switchedAccount.mutate();
switchedAccount.flush();
assert.deepEqual(switchedAccount.messages, [
  { handle: 'ownera', href: 'https://x.com/OwnerA' },
  { handle: null, href: null },
  { handle: 'ownerb', href: 'https://x.com/OwnerB' },
], 'account switching clears the missing account before reporting the replacement');
switchedAccount.state.href = '/RenamedOwner';
switchedAccount.poll();
switchedAccount.state.href = '/RENAMEDOWNER';
switchedAccount.mutate();
switchedAccount.flush();
assert.deepEqual(switchedAccount.messages.slice(3), [
  { handle: 'renamedowner', href: 'https://x.com/RenamedOwner' },
], 'renaming reports the new normalized handle once while preserving earlier observations');
const delayed = fixture({ href: null });
assert.equal(delayed.messages[0]?.handle, null);
delayed.state.href = '/SecondOwner';
delayed.mutate();
assert.equal(delayed.messages.length, 1, 'wait for debounce');
delayed.flush();
assert.equal(delayed.messages[1]?.handle, 'secondowner');
delayed.poll();
assert.equal(delayed.messages.length, 2, 'unchanged handles are suppressed');
delayed.state.href = null;
delayed.poll();
assert.equal(delayed.messages[2]?.handle, null, 'logout clears the observation');
delayed.state.href = '/SecondOwner';
delayed.poll();
assert.equal(delayed.messages[3]?.handle, 'secondowner', 'reappearance can be observed');
for (const options of [
  { url: 'https://x.com/i/flow/login' }, { url: 'https://x.com/login' },
  { url: 'https://x.com/logout' }, { url: 'https://x.com/signup' },
  { dedicated: false }, { href: '/OtherUser', dedicated: false },
  { href: '/home' }, { href: '/LOGIN' }, { href: '/settings' },
  { href: '/alice/status/123' }, { href: '/alice//' }, { href: '/a-b' },
  { href: '/abcdefghijklmnop' }, { href: '/caf%C3%A9' }, { href: '/%61lice' },
  { href: 'https://www.x.com/alice' }, { href: 'https://evil.test/alice' },
  { href: 'http://x.com/alice' }, { href: 'https://user@x.com/alice' },
  { href: '::::' }, { href: '' },
]) {
  assert.equal(fixture(options).messages[0]?.handle, null, JSON.stringify(options));
}
for (const options of [
  { subframe: true }, { url: 'https://evil.test/home' },
  { url: 'http://x.com/home' }, { url: 'https://x.com:8443/home' },
]) assert.equal(fixture(options).messages.length, 0, JSON.stringify(options));
assert.equal(fixture({ url: 'https://www.x.com/home', href: '/Alice/' }).messages[0]?.handle, 'alice');
const stopped = fixture();
stopped.mutate();
const queuedBeforeStop = stopped.queuedCallbacks();
stopped.stop();
for (const callback of queuedBeforeStop) callback();
const readsBeforeStop = stopped.state.reads;
stopped.state.href = '/AnotherOwner';
stopped.flush();
stopped.poll();
stopped.mutate();
stopped.flush();
assert.equal(stopped.state.reads, readsBeforeStop, 'stopping an open document cancels every account read');
assert.equal(stopped.messages.length, 1, 'stopping prevents queued observations');
assert.equal(stopped.queuedCallbacks().length, 0, 'stop removes mutation, interval, and debounce work');
stopped.start();
assert.equal(stopped.messages[1]?.handle, 'anotherowner', 'reenabling an existing document reads its current account');
assert.equal(stopped.contexts[1]?.generation, 'generation-2', 'reenabling never reuses an old choice generation');
for (const callback of queuedBeforeStop) callback();
assert.equal(stopped.messages.length, 2, 'callbacks from the old generation remain inert after re-enabling');
const otherWindow = fixture({ href: '/Independent' });
assert.equal(otherWindow.messages[0]?.handle, 'independent');
stopped.state.href = null;
stopped.poll();
assert.equal(otherWindow.messages.length, 1, 'one document logout does not modify another document');
console.log('X account observer fixtures passed');
