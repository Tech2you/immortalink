'use strict';
const url = new URL(window.location.href);
const pathMatch = url.pathname.match(/^\/invite\/([^/]+)\/?$/);
let code = '';
try {
  const value = pathMatch ? decodeURIComponent(pathMatch[1])
    : ['/invite', '/join'].includes(url.pathname) ? url.searchParams.get('code') || '' : '';
  code = value.replace(/\s/g, '').toUpperCase();
} catch (_) { /* Malformed links stay on the invalid-invitation screen. */ }

if (/^[A-Z0-9]{4,64}$/.test(code)) {
  document.getElementById('message').textContent = "You've been invited to join your family.";
  document.getElementById('code').textContent = code;
  document.getElementById('open').href = 'com.everroots.app://join?code=' + encodeURIComponent(code);
  document.getElementById('invite').hidden = false;
  document.getElementById('copy').addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(code);
      document.getElementById('status').textContent = 'Invite code copied.';
    } catch (_) {
      document.getElementById('status').textContent = 'Select and copy the invite code above.';
    }
  });
} else if (url.pathname !== '/') {
  document.getElementById('message').textContent = 'This invite link is incomplete or invalid. Ask your family for a new invitation.';
}
