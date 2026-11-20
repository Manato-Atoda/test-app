(function () {
  'use strict';
  const q = new URLSearchParams(location.search);
  const redirectUri = q.get('redirect_uri') || '';
  const codeChallenge = q.get('code_challenge') || '';
  const state = q.get('state') || '';
  const msg = document.getElementById('message');
  const company = document.getElementById('company');
  const submit = document.getElementById('submit');
  const back = document.getElementById('back');

  company.value = q.get('company') || '';

  function show(text, kind) {
    msg.textContent = text;
    msg.className = 'alert ' + (kind || 'error');
  }

  function backUrl(error) {
    if (!redirectUri) return '';
    const sep = redirectUri.indexOf('?') >= 0 ? '&' : '?';
    return redirectUri + sep + new URLSearchParams({ error: error, state: state }).toString();
  }

  if (redirectUri) {
    back.href = backUrl('cancelled');
  } else {
    document.getElementById('back-wrap').classList.add('hidden');
    show('このページはアプリの「パスキーでログイン」から開いてください。', 'warn');
    submit.disabled = true;
  }
  if (!TsunaguPasskey.supported()) {
    show('このブラウザ・接続先ではパスキーを使えません。パスワードでログインしてください。');
    submit.disabled = true;
  }

  document.getElementById('form').addEventListener('submit', async function (ev) {
    ev.preventDefault();
    if (!company.value.trim()) {
      show('企業コードを入力してください。');
      return;
    }
    submit.disabled = true;
    show('本人確認をしています…', 'ok');
    try {
      const result = await TsunaguPasskey.login({
        companyCode: company.value.trim(),
        loginId: q.get('login_id') || '',
        appRedirect: { redirect_uri: redirectUri, code_challenge: codeChallenge, state: state },
      });
      show('ログインしました。アプリに戻ります…', 'ok');
      location.href = result.redirect_url;
    } catch (err) {
      show(TsunaguPasskey.friendlyError(err));
      submit.disabled = false;
    }
  });
})();
