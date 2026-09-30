import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../Sources/SlopFactory/XWebPoster.swift', import.meta.url), 'utf8');
const selectors = {
  rootSelector: '[role="dialog"]',
  editorSelector: '[data-testid="tweetTextarea_0"] [contenteditable="true"], [data-testid="tweetTextarea_0"][contenteditable="true"]',
  textareaSelector: '[data-testid="tweetTextarea_0"]',
  fileInputSelector: 'input[type="file"]',
  postButtonSelector: '[data-testid="tweetButton"], [data-testid="tweetButtonInline"]',
  videoPreviewSelector: '[data-testid="attachments"] video, [data-testid="attachments"] [data-testid="videoPlayer"], [data-testid="attachments"] [data-testid="videoComponent"], [data-testid="media-container"] video, [data-testid="videoPlayer"], [data-testid="videoComponent"]',
};

function script(name) {
  const match = source.match(new RegExp(`private static let ${name} = """\\n([\\s\\S]*?)\\n    """`));
  assert.ok(match, `could not extract ${name}`);
  return match[1].split('\n').map(line => line.replace(/^    /, '')).join('\n')
    .replace(/\\\(XComposeDialog\.literal\(XComposeDialog\.(\w+)\)\)/g,
      (_, key) => JSON.stringify(selectors[key]));
}

class Button {
  constructor(disabled = false) { this.disabled = disabled; this.clicked = 0; }
  getClientRects() { return [1]; }
  getAttribute(name) { return name === 'aria-disabled' ? (this.disabled ? 'true' : null) : null; }
  click() { this.clicked++; }
}

function fixture({ dialog = true, dialogVideo = false, dialogDisabled = false, timelineVideo = false } = {}) {
  const dialogButton = new Button(dialogDisabled);
  const timelineButton = new Button();
  const empty = { style: { width: '0%' } };
  const compose = {
    querySelectorAll(selector) { return selector === selectors.postButtonSelector ? [dialogButton] : []; },
    querySelector(selector) {
      if (selector === selectors.videoPreviewSelector) return dialogVideo ? {} : null;
      if (selector === '[data-testid="progressBar-bar"]') return empty;
      if (selector === '[data-testid="attachments"] [role="progressbar"]') return null;
      return null;
    },
    listeners: [],
    addEventListener(type, listener) { this.listeners.push([type, listener]); },
  };
  const timeline = {
    querySelectorAll(selector) { return selector === selectors.postButtonSelector ? [timelineButton] : []; },
    querySelector(selector) { return selector === selectors.videoPreviewSelector && timelineVideo ? {} : null; },
  };
  const document = {
    querySelector(selector) {
      if (selector === selectors.rootSelector) return dialog ? compose : null;
      if (selector === selectors.videoPreviewSelector) return timelineVideo ? {} : dialogVideo ? {} : null;
      return null;
    },
    querySelectorAll(selector) { return selector === selectors.postButtonSelector ? [timelineButton, dialogButton] : []; },
  };
  return { document, compose, dialogButton, timelineButton, timeline };
}

function run(name, setup) {
  const state = setup;
  return vm.runInNewContext(script(name), {
    document: state.document,
    Element: class {},
    window: { webkit: { messageHandlers: { slopManualPostClick: { postMessage() {} } } } },
  });
}

const both = fixture({ dialogVideo: false, timelineVideo: true });
assert.equal(run('uploadReady', both), false, 'timeline video must not satisfy dialog upload readiness');

const disabled = fixture({ dialogVideo: true, dialogDisabled: true, timelineVideo: true });
assert.equal(run('uploadReady', disabled), false, 'disabled dialog Post button must not be ready');

const ready = fixture({ dialogVideo: true, timelineVideo: true });
assert.equal(run('uploadReady', ready), true);
assert.equal(run('clickPost', ready), true);
assert.equal(ready.dialogButton.clicked, 1, 'only the dialog Post button is clicked');
assert.equal(ready.timelineButton.clicked, 0, 'timeline Post button is untouched');
assert.equal(run('observeManualPostClick', ready), true);
assert.equal(ready.compose.listeners.length, 1, 'manual click observation is attached to the dialog');

const missing = fixture({ dialog: false, timelineVideo: true });
assert.equal(run('uploadReady', missing), false, 'missing dialog must fail readiness');
assert.equal(run('clickPost', missing), false, 'missing dialog must prevent posting');

console.log('X compose dialog selector fixtures passed');
