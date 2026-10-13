// Sign-in for the admin pages. Admins use their own Blindensport Graz
// account (Supabase); the server keeps the session in an HttpOnly cookie.
// Every page includes <div id="session"></div> and calls
// AdminSession.start(onReady), where onReady(info) loads the page's data.
// All API calls go through AdminSession.request(), which adds the anti-CSRF
// header the server requires and returns to the sign-in form on 401.
const AdminSession = (() => {
  const roleNames = { admin: 'Admin', root: 'Root', coach: 'Trainer:in', member: 'Mitglied' };
  let info = null;
  let onReady = () => {};
  const box = () => document.getElementById('session');
  const content = () => document.getElementById('content');

  function esc(s) {
    return String(s).replace(/[&<>"']/g, c => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]));
  }

  async function request(path, options) {
    const opts = Object.assign({}, options);
    opts.headers = Object.assign({ 'Content-Type': 'application/json', 'X-Requested-With': 'blindensport-admin' }, opts.headers);
    opts.credentials = 'same-origin';
    const res = await fetch(path, opts);
    if (res.status === 401 && path !== '/api/session') {
      showSignIn('Bitte erneut anmelden – die Sitzung ist abgelaufen.');
      throw new Error('Nicht angemeldet');
    }
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      throw new Error(body.reason || body.error || ('HTTP ' + res.status));
    }
    if (res.status === 204) return null;
    return res.json();
  }

  function showSignIn(message) {
    info = null;
    content().hidden = true;
    box().innerHTML =
      '<form id="signInForm" class="signin" aria-labelledby="signInTitle">' +
      '<h2 id="signInTitle">Anmelden</h2>' +
      '<p class="hint">Mit dem eigenen Blindensport-Graz-Konto (gleiche Anmeldung wie in der App). ' +
      'Zugriff haben Admins und Root.</p>' +
      '<label>E-Mail <input id="signInEmail" type="email" autocomplete="username" required></label>' +
      '<label>Passwort <input id="signInPassword" type="password" autocomplete="current-password" required></label>' +
      '<button type="submit">Anmelden</button>' +
      '<p id="signInStatus" role="alert">' + (message ? esc(message) : '') + '</p>' +
      '</form>';
    document.getElementById('signInForm').addEventListener('submit', signIn);
    document.getElementById('signInEmail').focus();
  }

  async function signIn(ev) {
    ev.preventDefault();
    const status = document.getElementById('signInStatus');
    status.textContent = 'Anmelden …';
    try {
      const result = await request('/api/session', {
        method: 'POST',
        body: JSON.stringify({
          email: document.getElementById('signInEmail').value,
          password: document.getElementById('signInPassword').value
        })
      });
      signedIn(result);
    } catch (e) {
      status.textContent = e.message === 'HTTP 401' ? 'E-Mail oder Passwort falsch.' : e.message;
      document.getElementById('signInPassword').value = '';
      document.getElementById('signInPassword').focus();
    }
  }

  function signedIn(result) {
    info = result;
    box().innerHTML =
      '<p class="session-bar">Angemeldet als <strong>' + esc(result.email) + '</strong> (' +
      esc(roleNames[result.role] || result.role) + ') <button type="button" id="signOutBtn">Abmelden</button></p>';
    document.getElementById('signOutBtn').addEventListener('click', signOut);
    content().hidden = false;
    onReady(result);
  }

  async function signOut() {
    await request('/api/session', { method: 'DELETE' }).catch(() => {});
    showSignIn('Abgemeldet.');
  }

  async function start(callback) {
    onReady = callback;
    try {
      signedIn(await request('/api/session'));
    } catch (e) {
      showSignIn('');
    }
  }

  return {
    start,
    request,
    can: permission => !!info && info.permissions.includes(permission)
  };
})();
