'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { GAME_URL, isGame, canNavigate, canPermit } = require('../policy.cjs');

test('website reload and OAuth round trip preserve existing URLs', () => {
  for (const url of [GAME_URL, `${GAME_URL}#discord_code=example`,
    'https://discord.com/oauth2/authorize?client_id=example',
    'https://discord.com/login',
    'https://game.chrisbox.dev/api/auth/discord/callback?code=example']) {
    assert.equal(canNavigate(url), true, url);
  }
});

test('reject unrelated sites, privileged schemes and lookalike origins', () => {
  for (const url of ['file:///etc/passwd', 'javascript:alert(1)', 'http://tfpp.github.io/the-game/',
    'https://tfpp.github.io.evil.test/the-game/', 'https://tfpp.github.io/other/',
    'https://tfpp.github.io/the-game/../other/', 'https://discord.com.evil.test/login',
    'https://discord.com/channels/@me', 'https://game.chrisbox.dev/api/me',
    'https://user:pass@tfpp.github.io/the-game/', 'invalid']) {
    assert.equal(canNavigate(url), false, url);
  }
});

test('only game input/display permissions are granted', () => {
  assert.equal(isGame(GAME_URL), true);
  for (const permission of ['pointerLock', 'fullscreen']) {
    assert.equal(canPermit(permission, GAME_URL), true);
    assert.equal(canPermit(permission, 'https://discord.com/login'), false);
  }
  for (const permission of ['media', 'geolocation', 'notifications', 'clipboard-read']) {
    assert.equal(canPermit(permission, GAME_URL), false);
  }
});
