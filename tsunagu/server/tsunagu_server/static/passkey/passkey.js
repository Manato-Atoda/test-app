// パスキー（WebAuthn）のブラウザ側の共通処理。サーバーとは base64url の JSON でやり取りする。
(function () {
  'use strict';

  function b64uToBuf(value) {
    const b64 = value.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((value.length + 3) % 4);
    const bin = atob(b64);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out.buffer;
  }

  function bufToB64u(buf) {
    const bytes = new Uint8Array(buf);
    let bin = '';
    for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
    return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }

  function creationOptions(pk) {
    return Object.assign({}, pk, {
      challenge: b64uToBuf(pk.challenge),
      user: Object.assign({}, pk.user, { id: b64uToBuf(pk.user.id) }),
      excludeCredentials: (pk.excludeCredentials || []).map((c) => Object.assign({}, c, { id: b64uToBuf(c.id) })),
    });
  }

  function requestOptions(pk) {
    return Object.assign({}, pk, {
      challenge: b64uToBuf(pk.challenge),
      allowCredentials: (pk.allowCredentials || []).map((c) => Object.assign({}, c, { id: b64uToBuf(c.id) })),
    });
  }

  function credentialJSON(cred) {
    const r = cred.response;
    const response = { clientDataJSON: bufToB64u(r.clientDataJSON) };
    if (r.attestationObject) {
      response.attestationObject = bufToB64u(r.attestationObject);
      response.transports = typeof r.getTransports === 'function' ? r.getTransports() : [];
    }
    if (r.authenticatorData) {
      response.authenticatorData = bufToB64u(r.authenticatorData);
      response.signature = bufToB64u(r.signature);
      if (r.userHandle) response.userHandle = bufToB64u(r.userHandle);
    }
    return { id: cred.id, rawId: bufToB64u(cred.rawId), type: cred.type, response };
  }

  async function postJSON(path, body, token) {
    const headers = { 'Content-Type': 'application/json' };
    if (token) headers.Authorization = 'Bearer ' + token;
    const res = await fetch(path, { method: 'POST', headers, body: JSON.stringify(body || {}) });
    const data = res.status === 204 ? {} : await res.json().catch(() => ({}));
    if (!res.ok) {
      const err = new Error((data.error && data.error.message) || '通信に失敗しました（' + res.status + '）');
      err.code = data.error && data.error.code;
      throw err;
    }
    return data;
  }

  function friendlyError(err) {
    if (!err) return 'エラーが発生しました';
    if (err.name === 'NotAllowedError') return 'パスキーの操作がキャンセルされたか、時間切れになりました。';
    if (err.name === 'InvalidStateError') return 'この端末のパスキーは既に登録されています。';
    if (err.name === 'SecurityError') return 'この接続先ではパスキーを使えません（HTTPS か localhost が必要です）。';
    if (err.name === 'NotSupportedError') return 'このブラウザ・端末はパスキーに対応していません。';
    return err.message || 'エラーが発生しました';
  }

  function supported() {
    return !!(window.PublicKeyCredential && navigator.credentials && window.isSecureContext);
  }

  // 登録: ticket（アプリから）または token（管理コンソールから）
  async function register({ ticket, token, name }) {
    const opts = await postJSON('/api/passkeys/register/options', ticket ? { ticket } : {}, token);
    const cred = await navigator.credentials.create({ publicKey: creationOptions(opts.publicKey) });
    return postJSON('/api/passkeys/register/verify', {
      challenge_id: opts.challenge_id, name: name || '', credential: credentialJSON(cred),
    });
  }

  // ログイン: appRedirect があればアプリに戻すための URL を返す
  async function login({ companyCode, loginId, appRedirect }) {
    const opts = await postJSON('/api/auth/passkey/options', { company_code: companyCode, login_id: loginId || '' });
    const cred = await navigator.credentials.get({ publicKey: requestOptions(opts.publicKey) });
    const body = { challenge_id: opts.challenge_id, credential: credentialJSON(cred) };
    if (appRedirect) body.app_redirect = appRedirect;
    return postJSON('/api/auth/passkey/verify', body);
  }

  window.TsunaguPasskey = { register, login, friendlyError, supported };
})();
