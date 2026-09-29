'use strict';

const GAME_URL = 'https://tfpp.github.io/the-game/';

function parse(value) {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && !url.username && !url.password ? url : null;
  } catch {
    return null;
  }
}

function isGame(value) {
  const url = parse(value);
  return !!url && url.origin === 'https://tfpp.github.io' &&
    url.pathname.startsWith('/the-game/');
}

function canNavigate(value) {
  const url = parse(value);
  if (!url) return false;
  return isGame(value) ||
    (url.origin === 'https://discord.com' &&
      ['/login', '/register', '/oauth2/authorize'].includes(url.pathname)) ||
    (url.origin === 'https://game.chrisbox.dev' &&
      url.pathname === '/api/auth/discord/callback');
}

function canPermit(permission, value) {
  return isGame(value) && ['pointerLock', 'fullscreen'].includes(permission);
}

module.exports = { GAME_URL, isGame, canNavigate, canPermit };
