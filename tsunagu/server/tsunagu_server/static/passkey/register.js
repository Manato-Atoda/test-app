(function () {
  'use strict';
  const q = new URLSearchParams(location.search);
  const ticket = q.get('ticket') || '';
  const redirectUri = q.get('redirect_uri') || '';
  const state = q.get('state') || '';
  const msg = document.getElementById('message');
  const name = document.getElementById('name');
  const submit = document.getElementById('submit');
  const back = document.getElementById('back');

  name.value = q.get('name') || '';

  function show(text, kind) {
    msg.textContent = text;
    msg.className = 'alert ' + (kind || 'error');
  }

  function returnUrl(params) {
    const sep = redirectUri.indexOf('?') >= 0 ? '&' : '?';
    return redirectUri + sep + new URLSearchParams(Object.assign({ state: state }, params)).toString();
  }

  if (redirectUri) {
    back.href = returnUrl({ error: 'cancelled' });
  } else {
    document.getElementById('back-wrap').classList.add('hidden');
  }
  if (!ticket) {
    show('登録用のリンクが正しくありません。アプリの「パスキー」からやり直してください。');
    submit.disabled = true;
  } else if (!TsunaguPasskey.supported()) {
    show('このブラウザ・接続先ではパスキーを使えません。');
    submit.disabled = true;
  }

  document.getElementById('form').addEventListener('submit', async function (ev) {
    ev.preventDefault();
    submit.disabled = true;
    show('登録しています…', 'ok');
    try {
      await TsunaguPasskey.register({ ticket: ticket, name: name.value.trim() });
      if (redirectUri) {
        show('登録しました。アプリに戻ります…', 'ok');
        location.href = returnUrl({ status: 'ok' });
      } else {
        show('登録しました。このページを閉じてください。', 'ok');
      }
    } catch (err) {
      // 登録用のチケットは 1 回限りなので、失敗したらアプリからやり直してもらう
      show(TsunaguPasskey.friendlyError(err) + ' アプリに戻って、もう一度お試しください。');
    }
  });
})();
