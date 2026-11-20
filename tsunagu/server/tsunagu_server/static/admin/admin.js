// 管理コンソール（企業管理者用）。ビルド不要の素の JavaScript。
// トークンは sessionStorage（タブを閉じると消える）に置く。
(function () {
  'use strict';

  const TOKEN_KEY = 'tsunagu_admin_token';
  const root = document.getElementById('root');
  const S = {
    token: null, me: null, company: null, tempPassword: '', view: 'dashboard', openReports: 0,
  };
  try { S.token = sessionStorage.getItem(TOKEN_KEY); } catch (e) { S.token = null; }

  // ------------------------------------------------------------ 小道具
  function h(tag, attrs) {
    const el = document.createElement(tag);
    const a = attrs || {};
    Object.keys(a).forEach(function (k) {
      const v = a[k];
      if (v === null || v === undefined || v === false) return;
      if (k.slice(0, 2) === 'on' && typeof v === 'function') el.addEventListener(k.slice(2), v);
      else if (k === 'class') el.className = v;
      else if (k === 'value') el.value = v;
      else if (k === 'checked') el.checked = !!v;
      else el.setAttribute(k, v === true ? '' : String(v));
    });
    for (let i = 2; i < arguments.length; i++) append(el, arguments[i]);
    return el;
  }
  function append(el, child) {
    if (child === null || child === undefined || child === false) return;
    if (Array.isArray(child)) { child.forEach(function (c) { append(el, c); }); return; }
    el.append(child instanceof Node ? child : String(child));
  }
  function clear(el) { while (el.firstChild) el.removeChild(el.firstChild); }

  function fmt(iso, withTime) {
    if (!iso) return '—';
    const d = new Date(iso);
    const opt = { year: 'numeric', month: '2-digit', day: '2-digit' };
    if (withTime !== false) { opt.hour = '2-digit'; opt.minute = '2-digit'; }
    return d.toLocaleString('ja-JP', opt);
  }

  function fmtShort(iso) {
    if (!iso) return '—';
    const d = new Date(iso);
    return (d.getMonth() + 1) + '/' + d.getDate() + ' ' + String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
  }

  let toastTimer = null;
  function toast(text) {
    const t = document.getElementById('toast');
    t.textContent = text;
    t.classList.remove('hidden');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { t.classList.add('hidden'); }, 3200);
  }

  function setToken(token) {
    S.token = token;
    try {
      if (token) sessionStorage.setItem(TOKEN_KEY, token); else sessionStorage.removeItem(TOKEN_KEY);
    } catch (e) { /* 保存できなくても動作は続ける */ }
  }

  async function api(method, path, body, opts) {
    opts = opts || {};
    const headers = {};
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    if (S.token) headers.Authorization = 'Bearer ' + S.token;
    const res = await fetch(path, { method: method, headers: headers, body: body !== undefined ? JSON.stringify(body) : undefined });
    if (opts.blob && res.ok) return { blob: await res.blob(), headers: res.headers };
    const data = res.status === 204 ? {} : await res.json().catch(function () { return {}; });
    if (!res.ok) {
      const info = data.error || {};
      const err = new Error(info.message || ('通信に失敗しました（' + res.status + '）'));
      err.code = info.code; err.info = info; err.status = res.status;
      if (res.status === 401 && !opts.quiet401) { setToken(null); renderLogin(err.message); }
      if (info.code === 'password_change_required') { renderPasswordChange(); }
      throw err;
    }
    return data;
  }

  function saveBlob(blob, headers, fallback) {
    let name = fallback;
    const cd = headers.get('Content-Disposition') || '';
    const m = /filename\*=UTF-8''([^;]+)/.exec(cd);
    if (m) name = decodeURIComponent(m[1]);
    const url = URL.createObjectURL(blob);
    const a = h('a', { href: url, download: name });
    document.body.append(a);
    a.click();
    a.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 10000);
  }

  function modal(title, body, actions) {
    const backdrop = h('div', { class: 'modal-backdrop' });
    const box = h('div', { class: 'card modal', role: 'dialog', 'aria-modal': 'true', 'aria-label': title });
    const close = function () { backdrop.remove(); document.removeEventListener('keydown', onKey); };
    const onKey = function (ev) { if (ev.key === 'Escape') close(); };
    document.addEventListener('keydown', onKey);
    box.append(h('h2', null, title), body);
    const bar = h('div', { class: 'actions' });
    (actions || []).forEach(function (a) {
      bar.append(h('button', { class: 'btn ' + (a.kind || ''), type: 'button', onclick: function () { a.onClick(close); } }, a.label));
    });
    if (actions && actions.length) box.append(bar);
    backdrop.append(box);
    backdrop.addEventListener('mousedown', function (ev) { if (ev.target === backdrop) close(); });
    document.body.append(backdrop);
    const first = box.querySelector('input, select, textarea');
    if (first) first.focus();
    return close;
  }

  function errorBox() { return h('div', { class: 'alert error hidden', role: 'alert' }); }
  function showError(box, err) { box.textContent = err.message || String(err); box.classList.remove('hidden'); }

  function field(label, input, hint) {
    const id = 'f' + Math.random().toString(36).slice(2);
    input.id = id;
    return h('div', { class: 'field' }, h('label', { for: id }, label), input, hint ? h('span', { class: 'hint' }, hint) : null);
  }
  function input(attrs) { return h('input', Object.assign({ class: 'input' }, attrs || {})); }
  function select(options, value) {
    const el = h('select', { class: 'input' });
    options.forEach(function (o) { el.append(h('option', { value: o[0] }, o[1])); });
    if (value !== undefined) el.value = value;
    return el;
  }

  const STATE_LABEL = {
    not_issued: ['未発行', ''], pending_first_login: ['初回ログイン待ち', 'warn'], temp_expired: ['仮パスワード期限切れ', 'danger'],
    active: ['利用中', 'ok'], locked: ['ロック中', 'danger'], suspended: ['利用停止', ''], retired: ['退職', ''],
  };
  function stateBadge(state) {
    const s = STATE_LABEL[state] || [state, ''];
    return h('span', { class: 'badge ' + s[1] }, s[0]);
  }

  // ------------------------------------------------------------ ログイン
  function renderLogin(message) {
    clear(root);
    const err = errorBox();
    const company = input({ autocomplete: 'organization', class: 'input mono', autocapitalize: 'characters' });
    const loginId = input({ autocomplete: 'username' });
    const password = input({ type: 'password', autocomplete: 'current-password' });
    try {
      company.value = localStorage.getItem('tsunagu_admin_company') || '';
      loginId.value = localStorage.getItem('tsunagu_admin_login') || '';
    } catch (e) { /* なくてもよい */ }
    const submit = h('button', { class: 'btn primary block', type: 'submit' }, 'ログイン');
    const form = h('form', { novalidate: true }, err,
      field('企業コード', company),
      field('社員コード または メールアドレス', loginId),
      field('パスワード', password),
      submit);
    form.addEventListener('submit', async function (ev) {
      ev.preventDefault();
      submit.disabled = true;
      err.classList.add('hidden');
      try {
        const data = await api('POST', '/api/auth/login', {
          company_code: company.value, login_id: loginId.value, password: password.value,
          device: { platform: 'web', name: '管理コンソール' },
        }, { quiet401: true });
        try {
          localStorage.setItem('tsunagu_admin_company', company.value.trim());
          localStorage.setItem('tsunagu_admin_login', loginId.value.trim());
        } catch (e) { /* なくてもよい */ }
        afterLogin(data, password.value);
      } catch (e) {
        showError(err, e);
      } finally {
        submit.disabled = false;
      }
    });
    const passkeyBtn = h('button', { class: 'btn block', type: 'button' }, 'パスキーでログイン');
    passkeyBtn.addEventListener('click', async function () {
      err.classList.add('hidden');
      if (!company.value.trim()) { showError(err, new Error('企業コードを入力してください')); return; }
      passkeyBtn.disabled = true;
      try {
        const data = await TsunaguPasskey.login({ companyCode: company.value.trim(), loginId: loginId.value.trim() });
        afterLogin(data, '');
      } catch (e) {
        showError(err, new Error(TsunaguPasskey.friendlyError(e)));
      } finally {
        passkeyBtn.disabled = false;
      }
    });
    if (!TsunaguPasskey.supported()) passkeyBtn.disabled = true;
    root.append(h('main', { class: 'login-wrap' }, h('section', { class: 'card login-card' },
      h('span', { class: 'brandmark' }, h('span', { class: 'logo' }, 'つ'), 'つなぐ'),
      h('h1', null, '管理コンソール'),
      h('p', { class: 'muted' }, '企業管理者のアカウントでログインしてください。'),
      message ? h('div', { class: 'alert warn' }, message) : null,
      form,
      h('div', { class: 'divider' }, 'または'),
      passkeyBtn)));
    (company.value ? (loginId.value ? password : loginId) : company).focus();
  }

  function afterLogin(data, password) {
    setToken(data.token);
    S.me = data.user;
    S.company = data.company;
    if (data.status === 'password_change_required') {
      S.tempPassword = password;
      renderPasswordChange();
      return;
    }
    if (S.me.role !== 'admin') {
      api('POST', '/api/auth/logout').catch(function () {});
      setToken(null);
      renderLogin('管理者の権限がないアカウントです。社員の方はアプリをご利用ください。');
      return;
    }
    renderShell();
  }

  // ------------------------------------------------------------ パスワード再設定
  async function renderPasswordChange() {
    clear(root);
    let policy = { min_length: 8, require_symbol: false };
    try { policy = await api('GET', '/api/auth/password-policy'); } catch (e) { /* 既定値で表示 */ }
    const err = errorBox();
    const current = input({ type: 'password', autocomplete: 'current-password' });
    current.value = S.tempPassword || '';
    const next = input({ type: 'password', autocomplete: 'new-password' });
    const confirm = input({ type: 'password', autocomplete: 'new-password' });
    const rules = [
      ['len', policy.min_length + '文字以上', function (p) { return p.length >= policy.min_length; }],
      ['alpha', '英字を含む', function (p) { return /[A-Za-z]/.test(p); }],
      ['digit', '数字を含む', function (p) { return /[0-9]/.test(p); }],
    ];
    if (policy.require_symbol) rules.push(['sym', '記号を含む', function (p) { return /[!-\/:-@\[-`{-~]/.test(p); }]);
    rules.push(['chars', '半角の英数字・記号だけ（空白・全角なし）', function (p) { return p.length > 0 && /^[!-~]+$/.test(p); }]);
    rules.push(['same', '確認用と一致', function (p) { return p.length > 0 && p === confirm.value; }]);
    const list = h('ul', { class: 'rules' });
    const items = rules.map(function (r) { const li = h('li', null, r[1]); list.append(li); return li; });
    function update() { rules.forEach(function (r, i) { items[i].classList.toggle('ok', r[2](next.value)); }); }
    next.addEventListener('input', update);
    confirm.addEventListener('input', update);
    const submit = h('button', { class: 'btn primary block', type: 'submit' }, 'パスワードを設定');
    const form = h('form', { novalidate: true }, err,
      S.tempPassword ? null : field('現在のパスワード（仮パスワード）', current),
      field('新しいパスワード', next), field('新しいパスワード（確認）', confirm), list, submit);
    form.addEventListener('submit', async function (ev) {
      ev.preventDefault();
      err.classList.add('hidden');
      if (next.value !== confirm.value) { showError(err, new Error('確認用のパスワードが一致しません')); return; }
      submit.disabled = true;
      try {
        const data = await api('POST', '/api/auth/change-password', { current_password: current.value, new_password: next.value });
        S.tempPassword = '';
        toast('パスワードを設定しました');
        afterLogin(data, '');
      } catch (e) {
        showError(err, e);
      } finally {
        submit.disabled = false;
      }
    });
    root.append(h('main', { class: 'login-wrap' }, h('section', { class: 'card login-card' },
      h('span', { class: 'brandmark' }, h('span', { class: 'logo' }, 'つ'), 'つなぐ'),
      h('h1', null, '新しいパスワードを設定'),
      h('p', { class: 'muted' }, '初回ログインのため、仮パスワードから自分だけのパスワードに変更してください。記号も使えます。'),
      form,
      h('button', { class: 'btn block', type: 'button', onclick: logout }, 'ログアウト'))));
    next.focus();
  }

  async function logout() {
    try { await api('POST', '/api/auth/logout', undefined, { quiet401: true }); } catch (e) { /* 失効済みでもよい */ }
    setToken(null);
    S.me = null;
    renderLogin('ログアウトしました。');
  }

  // ------------------------------------------------------------ 画面の枠
  const NAV = [
    ['dashboard', 'ダッシュボード'], ['users', '社員アカウント'], ['channels', 'チャンネル'], ['reports', '通報'],
    ['audit', '監査ログ'], ['settings', 'セキュリティ・規程'], ['mail', 'メール送信履歴'], ['account', '自分のアカウント'],
  ];
  let main = null;

  function renderShell() {
    clear(root);
    const nav = h('nav', { class: 'sidebar', 'aria-label': 'メニュー' },
      h('span', { class: 'brandmark' }, h('span', { class: 'logo' }, 'つ'), 'つなぐ'),
      h('div', { class: 'company' }, h('strong', null, S.company.name), '企業コード ' + S.company.code));
    NAV.forEach(function (n) {
      const btn = h('button', { class: 'nav-item' + (S.view === n[0] ? ' active' : ''), type: 'button' }, n[1],
        n[0] === 'reports' && S.openReports ? h('span', { class: 'count' }, S.openReports) : null);
      btn.addEventListener('click', function () { S.view = n[0]; renderShell(); });
      nav.append(btn);
    });
    nav.append(h('div', { class: 'spacer' }),
      h('div', { class: 'me' }, h('strong', null, S.me.display_name), S.me.employee_code + '・管理者'),
      h('button', { class: 'nav-item', type: 'button', onclick: logout }, 'ログアウト'));
    main = h('main', { class: 'main' });
    root.append(h('div', { class: 'shell' }, nav, main));
    const views = { dashboard: viewDashboard, users: viewUsers, channels: viewChannels, reports: viewReports,
      audit: viewAudit, settings: viewSettings, mail: viewMail, account: viewAccount };
    (views[S.view] || viewDashboard)().catch(function (e) {
      if (e.status !== 401) main.append(h('div', { class: 'alert error' }, e.message));
    });
  }

  function head(title, desc, actions) {
    return h('div', { class: 'page-head' }, h('div', null, h('h1', null, title), desc ? h('p', null, desc) : null),
      actions ? h('div', { class: 'toolbar' }, actions) : null);
  }

  // ------------------------------------------------------------ ダッシュボード
  async function viewDashboard() {
    const st = await api('GET', '/api/admin/stats');
    S.openReports = st.open_reports;
    const states = st.account_states || {};
    function stat(label, value, cls) {
      return h('div', { class: 'card stat' }, h('div', { class: 'label' }, label), h('div', { class: 'value ' + (cls || '') }, value));
    }
    main.append(head('ダッシュボード', S.company.name + ' の利用状況'));
    if (st.mail_mode !== 'smtp') {
      main.append(h('div', { class: 'alert warn' }, '開発モード：メールは実際には送信されず、「メール送信履歴」に保存されます。'));
    }
    main.append(h('div', { class: 'stats' },
      stat('在籍アカウント', st.users_total),
      stat('未発行', states.not_issued || 0, states.not_issued ? 'warn' : ''),
      stat('初回ログイン待ち', states.pending_first_login || 0),
      stat('仮パスワード期限切れ', states.temp_expired || 0, states.temp_expired ? 'danger' : ''),
      stat('ロック中', states.locked || 0, states.locked ? 'danger' : ''),
      stat('7日間にログインした人', st.active_users_7d),
      stat('7日間の投稿', st.posts_7d),
      stat('未対応の通報', st.open_reports, st.open_reports ? 'danger' : '')));
    main.append(h('section', { class: 'card section' },
      h('h2', null, 'アカウント発行の流れ'),
      h('ol', null,
        h('li', null, '「社員アカウント」で社員を登録（1人ずつ、または CSV で一括）'),
        h('li', null, '社員を選んで「PDFで発行」または「メールで発行」— 仮パスワードはこのときだけ作られ、サーバーには残りません'),
        h('li', null, '社員は企業コード・社員コード（またはメール）・仮パスワードでログインし、初回に自分のパスワードを設定'),
        h('li', null, '必要に応じて、アプリの設定からパスキーを登録')),
      h('button', { class: 'btn primary', type: 'button', onclick: function () { S.view = 'users'; renderShell(); } }, '社員アカウントへ')));
  }

  // ------------------------------------------------------------ 社員アカウント
  async function viewUsers() {
    const selected = new Set();
    const q = input({ type: 'search', placeholder: '氏名・社員コード・部署・メールで検索' });
    const stateSel = select([['', 'すべての状態']].concat(Object.keys(STATE_LABEL).map(function (k) { return [k, STATE_LABEL[k][0]]; })));
    const bulk = h('div', { class: 'bulkbar hidden' });
    const tableBox = h('div', { class: 'card table-wrap' });
    let users = [];

    main.append(head('社員アカウント', '社員の登録と、ログイン情報（仮パスワード）の発行を行います。', [
      h('button', { class: 'btn primary', type: 'button', onclick: function () { userForm(null, reload); } }, '社員を追加'),
      h('button', { class: 'btn', type: 'button', onclick: function () { importDialog(reload); } }, 'CSVで一括登録'),
      h('button', { class: 'btn', type: 'button', onclick: exportUsers }, 'CSV出力'),
    ]));
    main.append(h('div', { class: 'toolbar' }, q, stateSel), bulk, tableBox);

    let timer = null;
    q.addEventListener('input', function () { clearTimeout(timer); timer = setTimeout(reload, 250); });
    stateSel.addEventListener('change', reload);

    function renderBulk() {
      clear(bulk);
      bulk.classList.toggle('hidden', selected.size === 0);
      if (!selected.size) return;
      bulk.append(selected.size + '人を選択中',
        h('button', { class: 'btn small primary', type: 'button', onclick: function () { issueDialog(Array.from(selected), 'pdf', reload); } }, 'PDFで発行'),
        h('button', { class: 'btn small', type: 'button', onclick: function () { issueDialog(Array.from(selected), 'email', reload); } }, 'メールで発行'),
        h('button', { class: 'btn small', type: 'button', onclick: function () { selected.clear(); renderTable(); } }, '選択を解除'));
    }

    function renderTable() {
      clear(tableBox);
      renderBulk();
      if (!users.length) { tableBox.append(h('div', { class: 'empty' }, '該当する社員はいません')); return; }
      const all = h('input', { type: 'checkbox', 'aria-label': 'すべて選択', checked: users.every(function (u) { return selected.has(u.id); }) });
      all.addEventListener('change', function () {
        users.forEach(function (u) { if (all.checked) selected.add(u.id); else selected.delete(u.id); });
        renderTable();
      });
      const tbody = h('tbody');
      users.forEach(function (u) {
        const cb = h('input', { type: 'checkbox', 'aria-label': u.display_name + 'を選択', checked: selected.has(u.id) });
        cb.addEventListener('change', function () { if (cb.checked) selected.add(u.id); else selected.delete(u.id); renderBulk(); });
        tbody.append(h('tr', null,
          h('td', null, cb),
          h('td', { class: 'nowrap mono' }, u.employee_code),
          h('td', null, h('div', null, u.display_name, u.role === 'admin' ? h('span', { class: 'badge brand' }, ' 管理者') : null),
            h('div', { class: 'sub' }, [u.department, u.title].filter(Boolean).join('・') || '—')),
          h('td', { class: 'small' }, u.email || h('span', { class: 'muted' }, '未登録')),
          h('td', { class: 'nowrap' }, stateBadge(u.account_state),
            u.account_state === 'pending_first_login' && u.temp_password_expires_at
              ? h('div', { class: 'sub' }, '期限 ' + fmtShort(u.temp_password_expires_at)) : null,
            u.credentials_issued_at ? h('div', { class: 'sub' }, fmtShort(u.credentials_issued_at) + ' ' + ({ pdf: 'PDF', email: 'メール', cli: '初期設定' }[u.credentials_issued_via] || '') + 'で発行') : null),
          h('td', { class: 'small nowrap' }, u.last_login_at ? fmtShort(u.last_login_at) : '—', u.passkey_count ? h('div', { class: 'sub' }, 'パスキー ' + u.passkey_count + '件') : null),
          h('td', { class: 'nowrap' }, userMenu(u, reload))));
      });
      tableBox.append(h('table', { class: 'table' },
        h('thead', null, h('tr', null, h('th', null, all), h('th', null, '社員コード'), h('th', null, '氏名・所属'),
          h('th', null, 'メール'), h('th', null, '状態'), h('th', null, '最終ログイン'), h('th', null, ''))),
        tbody));
    }

    async function reload() {
      const params = new URLSearchParams({ q: q.value.trim(), state: stateSel.value });
      const data = await api('GET', '/api/admin/users?' + params.toString());
      users = data.users;
      const ids = new Set(users.map(function (u) { return u.id; }));
      Array.from(selected).forEach(function (id) { if (!ids.has(id)) selected.delete(id); });
      renderTable();
    }
    await reload();
  }

  function userMenu(u, reload) {
    const menu = h('details', { class: 'menu' });
    const list = h('div', { class: 'menu-list' });
    function item(label, fn, danger) {
      list.append(h('button', { type: 'button', class: danger ? 'danger' : '', onclick: function () { menu.open = false; fn(); } }, label));
    }
    async function act(path, body, done) {
      try { await api('POST', path, body); toast(done); reload(); } catch (e) { if (e.status !== 401) toast(e.message); }
    }
    item('編集', function () { userForm(u, reload); });
    if (u.status === 'active') {
      list.append(h('hr'));
      item('PDFで発行（仮パスワード）', function () { issueDialog([u.id], 'pdf', reload); });
      item('メールで発行（仮パスワード）', function () { issueDialog([u.id], 'email', reload); });
    }
    list.append(h('hr'));
    if (u.account_state === 'locked') item('ロックを解除', function () { act('/api/admin/users/' + u.id + '/unlock', {}, 'ロックを解除しました'); });
    item('すべての端末からログアウトさせる', function () { act('/api/admin/users/' + u.id + '/revoke-sessions', {}, 'ログアウトさせました'); });
    if (u.passkey_count) item('パスキーをすべて削除', function () { act('/api/admin/users/' + u.id + '/delete-passkeys', {}, 'パスキーを削除しました'); }, true);
    list.append(h('hr'));
    if (u.status === 'active') {
      item('利用停止にする', function () { confirmDialog('利用停止', u.display_name + ' さんを利用停止にします。ログイン中の端末もすべてログアウトされます。', function () { act('/api/admin/users/' + u.id + '/status', { status: 'suspended' }, '利用停止にしました'); }); }, true);
      item('退職にする', function () { confirmDialog('退職', u.display_name + ' さんを退職にします。ログインできなくなり、社員名簿にも表示されません（投稿は記録として残ります）。', function () { act('/api/admin/users/' + u.id + '/status', { status: 'retired' }, '退職にしました'); }); }, true);
    } else {
      item('利用を再開する', function () { act('/api/admin/users/' + u.id + '/status', { status: 'active' }, '利用を再開しました'); });
    }
    menu.append(h('summary', { class: 'btn small' }, '操作 ▾'), list);
    return menu;
  }

  function confirmDialog(title, text, onOk) {
    modal(title, h('p', null, text), [
      { label: 'キャンセル', onClick: function (close) { close(); } },
      { label: '実行する', kind: 'primary', onClick: function (close) { close(); onOk(); } },
    ]);
  }

  function userForm(u, reload) {
    const err = errorBox();
    const code = input({ class: 'input mono', value: u ? u.employee_code : '', disabled: !!u, maxlength: 32 });
    const name = input({ value: u ? u.display_name : '', maxlength: 60 });
    const email = input({ type: 'email', value: u ? (u.email || '') : '', maxlength: 254 });
    const dept = input({ value: u ? u.department : '', maxlength: 60 });
    const title = input({ value: u ? u.title : '', maxlength: 60 });
    const role = select([['member', '一般社員'], ['admin', '企業管理者']], u ? u.role : 'member');
    const issue = h('div', { class: 'radio-row' });
    [['none', 'あとで発行'], ['pdf', 'PDFで発行'], ['email', 'メールで発行']].forEach(function (o, i) {
      issue.append(h('label', null, h('input', { type: 'radio', name: 'issue', value: o[0], checked: i === 0 }), o[1]));
    });
    const body = h('div', null, err,
      h('div', { class: 'grid-2' },
        field('社員コード', code, u ? 'ログインIDなので変更できません' : '半角英数字と . _ -（例：E0123）'),
        field('氏名', name)),
      field('メールアドレス', email, 'ログインIDとしても使えます。メールで発行する場合は必須です。'),
      h('div', { class: 'grid-2' }, field('部署', dept), field('役職', title)),
      field('権限', role, '企業管理者はこの管理コンソールを使えます。'),
      u ? null : h('div', { class: 'field' }, h('label', null, '登録後のアカウント情報の発行'), issue));
    modal(u ? '社員情報の編集' : '社員を追加', body, [
      { label: 'キャンセル', onClick: function (close) { close(); } },
      { label: u ? '保存' : '登録', kind: 'primary', onClick: async function (close) {
        err.classList.add('hidden');
        const payload = { display_name: name.value, email: email.value, department: dept.value, title: title.value, role: role.value };
        try {
          let created;
          if (u) {
            await api('PATCH', '/api/admin/users/' + u.id, payload);
          } else {
            payload.employee_code = code.value;
            created = (await api('POST', '/api/admin/users', payload)).user;
          }
          close();
          toast(u ? '保存しました' : '登録しました');
          const method = body.querySelector('input[name=issue]:checked');
          if (created && method && method.value !== 'none') await issueNow([created.id], method.value);
          reload();
        } catch (e) { showError(err, e); }
      } },
    ]);
  }

  function issueDialog(ids, method, reload) {
    const label = method === 'pdf' ? 'PDF' : 'メール';
    const text = ids.length + '人分のアカウント情報を' + label + 'で発行します。新しい仮パスワードを作るため、' +
      'これまでのパスワード（仮パスワード含む）は使えなくなり、ログイン中の端末もログアウトされます。' +
      (method === 'pdf' ? ' PDF には仮パスワードが印字されます。配布後はファイルを削除してください。'
        : ' メールアドレスが未登録の社員はスキップされます。');
    modal(label + 'で発行', h('p', null, text), [
      { label: 'キャンセル', onClick: function (close) { close(); } },
      { label: '発行する', kind: 'primary', onClick: async function (close) { close(); await issueNow(ids, method); reload(); } },
    ]);
  }

  async function issueNow(ids, method) {
    try {
      if (method === 'pdf') {
        const res = await api('POST', '/api/admin/credentials', { user_ids: ids, method: 'pdf' }, { blob: true });
        saveBlob(res.blob, res.headers, 'account-notice.pdf');
        const skipped = Number(res.headers.get('X-Tsunagu-Skipped') || 0);
        toast(res.headers.get('X-Tsunagu-Issued') + '人分のPDFを発行しました' + (skipped ? '（' + skipped + '人は対象外）' : ''));
      } else {
        const data = await api('POST', '/api/admin/credentials', { user_ids: ids, method: 'email' });
        const lines = data.skipped.map(function (s) { return s.employee_code + '：' + s.reason; });
        if (lines.length || data.mail_mode !== 'smtp') {
          modal('メールで発行しました', h('div', null,
            h('p', null, data.sent.length + '人に送信しました。'),
            data.mail_mode !== 'smtp' ? h('div', { class: 'alert warn' }, '開発モードのため実際には送信していません。本文は「メール送信履歴」で確認できます。') : null,
            lines.length ? h('div', null, h('strong', null, '送信しなかった社員'), h('ul', null, lines.map(function (l) { return h('li', null, l); }))) : null),
          [{ label: '閉じる', kind: 'primary', onClick: function (close) { close(); } }]);
        } else {
          toast(data.sent.length + '人にメールを送信しました');
        }
      }
    } catch (e) {
      if (e.status !== 401) toast(e.message);
    }
  }

  function importDialog(reload) {
    const err = errorBox();
    const area = h('textarea', { class: 'input mono', rows: 8, placeholder: 'employee_code,display_name,email,department,title,role\nE0101,山田 花子,hanako@example.co.jp,営業部,主任,member' });
    const file = h('input', { type: 'file', accept: '.csv,text/csv' });
    file.addEventListener('change', function () {
      const f = file.files && file.files[0];
      if (!f) return;
      const reader = new FileReader();
      reader.onload = function () { area.value = String(reader.result || ''); };
      reader.readAsText(f, 'utf-8');
    });
    const template = h('button', { class: 'btn small', type: 'button' }, 'テンプレートをダウンロード');
    template.addEventListener('click', function () {
      const csv = '﻿employee_code,display_name,email,department,title,role\r\nE0101,山田 花子,hanako@example.co.jp,営業部,主任,member\r\n';
      saveBlob(new Blob([csv], { type: 'text/csv' }), new Headers(), 'tsunagu-users-template.csv');
    });
    const result = h('div');
    modal('CSVで一括登録', h('div', null, err,
      h('p', { class: 'small muted' }, '1行目は見出し（employee_code, display_name は必須。email, department, title, role は任意。日本語の見出し「社員コード・氏名・メールアドレス・部署・役職・権限」も使えます）。文字コードは UTF-8。'),
      h('div', { class: 'toolbar' }, file, template), area, result), [
      { label: '閉じる', onClick: function (close) { close(); reload(); } },
      { label: '取り込む', kind: 'primary', onClick: async function () {
        err.classList.add('hidden');
        clear(result);
        try {
          const data = await api('POST', '/api/admin/users/import', { csv: area.value });
          result.append(h('div', { class: 'alert ok' }, data.created + '人を登録しました。'));
          if (data.errors.length) {
            result.append(h('div', { class: 'alert error' }, h('strong', null, '登録できなかった行'),
              h('ul', null, data.errors.map(function (e) { return h('li', null, e.line + '行目：' + e.message); }))));
          }
          if (data.created_ids.length) {
            result.append(h('div', { class: 'toolbar' },
              h('button', { class: 'btn small primary', type: 'button', onclick: function () { issueDialog(data.created_ids, 'pdf', reload); } }, '登録した人の通知書をPDFで発行'),
              h('button', { class: 'btn small', type: 'button', onclick: function () { issueDialog(data.created_ids, 'email', reload); } }, 'メールで発行')));
          }
          area.value = '';
        } catch (e) { showError(err, e); }
      } },
    ]);
  }

  async function exportUsers() {
    try {
      const res = await api('GET', '/api/admin/users/export', undefined, { blob: true });
      saveBlob(res.blob, res.headers, 'users.csv');
    } catch (e) { if (e.status !== 401) toast(e.message); }
  }

  // ------------------------------------------------------------ チャンネル
  async function viewChannels() {
    const data = await api('GET', '/api/admin/channels');
    main.append(head('チャンネル', '全社チャンネルには全員が自動で参加します。非公開チャンネルは管理者がメンバーを決めます。', [
      h('button', { class: 'btn primary', type: 'button', onclick: function () { channelForm(null); } }, 'チャンネルを作成'),
    ]));
    const tbody = h('tbody');
    data.channels.forEach(function (c) {
      const kind = c.company_wide ? h('span', { class: 'badge brand' }, '全社') : c.visibility === 'private'
        ? h('span', { class: 'badge warn' }, '非公開') : h('span', { class: 'badge' }, '公開');
      tbody.append(h('tr', null,
        h('td', null, h('strong', null, c.name), h('div', { class: 'sub' }, c.description || '—')),
        h('td', null, kind),
        h('td', { class: 'small' }, c.post_policy === 'admins' ? '管理者のみ' : '全員'),
        h('td', { class: 'small' }, c.member_count + '人'),
        h('td', null, c.archived ? h('span', { class: 'badge' }, 'アーカイブ') : h('span', { class: 'badge ok' }, '利用中')),
        h('td', { class: 'nowrap' },
          h('button', { class: 'btn small', type: 'button', onclick: function () { channelForm(c); } }, '編集'), ' ',
          c.company_wide ? null : h('button', { class: 'btn small', type: 'button', onclick: function () { membersDialog(c); } }, 'メンバー'))));
    });
    main.append(h('div', { class: 'card table-wrap' }, h('table', { class: 'table' },
      h('thead', null, h('tr', null, h('th', null, 'チャンネル'), h('th', null, '種類'), h('th', null, '投稿できる人'),
        h('th', null, 'メンバー'), h('th', null, '状態'), h('th', null, ''))), tbody)));
  }

  function channelForm(c) {
    const err = errorBox();
    const name = input({ value: c ? c.name : '', maxlength: 40 });
    const desc = input({ value: c ? c.description : '', maxlength: 200 });
    const kind = select([['open', '公開（誰でも参加できる）'], ['private', '非公開（管理者が招待）'], ['company_wide', '全社（全員が自動で参加）']],
      c ? (c.company_wide ? 'company_wide' : c.visibility) : 'open');
    const policy = select([['everyone', '参加者全員'], ['admins', '管理者のみ（お知らせ用）']], c ? c.post_policy : 'everyone');
    const archived = h('input', { type: 'checkbox', checked: c ? c.archived : false });
    modal(c ? 'チャンネルの編集' : 'チャンネルを作成', h('div', null, err,
      field('名前', name), field('説明', desc), field('種類', kind), field('投稿できる人', policy),
      c ? h('label', { class: 'check' }, archived, 'アーカイブする（閲覧のみ・新しい投稿は不可）') : null), [
      { label: 'キャンセル', onClick: function (close) { close(); } },
      { label: c ? '保存' : '作成', kind: 'primary', onClick: async function (close) {
        const payload = { name: name.value, description: desc.value, post_policy: policy.value,
          company_wide: kind.value === 'company_wide', visibility: kind.value === 'private' ? 'private' : 'open' };
        if (c) payload.archived = archived.checked;
        try {
          if (c) await api('PATCH', '/api/admin/channels/' + c.id, payload); else await api('POST', '/api/admin/channels', payload);
          close();
          toast('保存しました');
          renderShell();
        } catch (e) { showError(err, e); }
      } },
    ]);
  }

  async function membersDialog(c) {
    const err = errorBox();
    const list = h('div');
    const codes = h('textarea', { class: 'input mono', rows: 3, placeholder: '社員コードを改行・カンマ区切りで（例：E0002, E0004）' });
    async function load() {
      clear(list);
      const data = await api('GET', '/api/admin/channels/' + c.id + '/members');
      if (!data.members.length) list.append(h('p', { class: 'muted' }, 'メンバーはいません'));
      data.members.forEach(function (m) {
        list.append(h('div', { class: 'list-item' },
          h('div', null, m.display_name, h('div', { class: 'small muted' }, m.employee_code + '・' + (m.department || '—'))),
          h('button', { class: 'btn small danger', type: 'button', onclick: async function () {
            try { await api('DELETE', '/api/admin/channels/' + c.id + '/members/' + m.id); load(); } catch (e) { showError(err, e); }
          } }, '外す')));
      });
    }
    modal('メンバー：' + c.name, h('div', null, err, list, field('メンバーを追加', codes)), [
      { label: '閉じる', onClick: function (close) { close(); renderShell(); } },
      { label: '追加', kind: 'primary', onClick: async function () {
        const values = codes.value.split(/[\s,、]+/).filter(Boolean);
        try {
          const data = await api('POST', '/api/admin/channels/' + c.id + '/members', { employee_codes: values });
          codes.value = '';
          toast(data.added + '人を追加しました' + (data.not_found.length ? '（見つからない社員コード：' + data.not_found.join(', ') + '）' : ''));
          load();
        } catch (e) { showError(err, e); }
      } },
    ]);
    load().catch(function (e) { showError(err, e); });
  }

  // ------------------------------------------------------------ 通報
  async function viewReports() {
    const data = await api('GET', '/api/admin/reports?status=open');
    S.openReports = data.reports.length;
    main.append(head('通報', '社員から通報された投稿・コメントです。内容を確認し、非表示にするか対応不要にしてください。'));
    if (!data.reports.length) { main.append(h('div', { class: 'card empty' }, '未対応の通報はありません')); return; }
    data.reports.forEach(function (r) {
      main.append(h('div', { class: 'card report' },
        h('div', { class: 'small muted' }, fmt(r.created_at) + '・' + (r.target_type === 'post' ? '投稿' : 'コメント') + '・通報者 ' + r.reporter.display_name),
        h('div', null, h('strong', null, '理由：'), r.reason),
        h('div', { class: 'body' }, r.target_removed ? '（既に削除・非表示になっています）' : r.body),
        h('div', { class: 'small muted' }, '投稿者：' + (r.author ? r.author.display_name + '（' + r.author.employee_code + '）' : '—')),
        h('div', { class: 'toolbar' },
          h('button', { class: 'btn small primary', type: 'button', onclick: function () { resolve(r.id, 'hide'); } }, '非表示にする'),
          h('button', { class: 'btn small', type: 'button', onclick: function () { resolve(r.id, 'dismiss'); } }, '対応不要'))));
    });
    async function resolve(id, action) {
      try { await api('POST', '/api/admin/reports/' + id + '/resolve', { action: action }); toast('対応しました'); renderShell(); }
      catch (e) { if (e.status !== 401) toast(e.message); }
    }
  }

  // ------------------------------------------------------------ 監査ログ
  async function viewAudit() {
    const tbody = h('tbody');
    const more = h('button', { class: 'btn', type: 'button' }, 'さらに読み込む');
    let before = null;
    main.append(head('監査ログ', 'ログイン・アカウント発行・管理操作などの記録です（仮パスワードやパスワードは記録しません）。', [
      h('button', { class: 'btn', type: 'button', onclick: async function () {
        try { const res = await api('GET', '/api/admin/audit-logs/export', undefined, { blob: true }); saveBlob(res.blob, res.headers, 'audit.csv'); }
        catch (e) { if (e.status !== 401) toast(e.message); }
      } }, 'CSV出力'),
    ]));
    main.append(h('div', { class: 'card table-wrap' }, h('table', { class: 'table' },
      h('thead', null, h('tr', null, h('th', null, '日時'), h('th', null, '操作'), h('th', null, '実行者'), h('th', null, '詳細'), h('th', null, 'IP'))),
      tbody)), h('div', { class: 'toolbar' }, more));
    async function load() {
      const data = await api('GET', '/api/admin/audit-logs' + (before ? '?before=' + before : ''));
      data.logs.forEach(function (l) {
        const detail = Object.keys(l.detail || {}).map(function (k) { return k + '=' + JSON.stringify(l.detail[k]); }).join(' ');
        tbody.append(h('tr', null,
          h('td', { class: 'small nowrap' }, fmt(l.created_at)),
          h('td', null, l.label, h('div', { class: 'sub mono' }, l.action)),
          h('td', { class: 'small' }, l.actor ? l.actor.display_name + '（' + l.actor.employee_code + '）' : '—'),
          h('td', { class: 'small mono' }, (l.target_type ? l.target_type + '#' + l.target_id + ' ' : '') + detail),
          h('td', { class: 'small mono' }, l.ip || '—')));
      });
      before = data.next_before;
      more.classList.toggle('hidden', !before);
    }
    more.addEventListener('click', function () { load().catch(function () {}); });
    await load();
  }

  // ------------------------------------------------------------ 設定
  async function viewSettings() {
    const data = await api('GET', '/api/admin/settings');
    const s = data.settings;
    const err = errorBox();
    const minLen = input({ type: 'number', min: 8, max: 64, value: s.password_min_length });
    const sym = h('input', { type: 'checkbox', checked: s.password_require_symbol });
    const ttl = input({ type: 'number', min: 1, max: 336, value: s.temp_password_ttl_hours });
    const lockN = input({ type: 'number', min: 3, max: 20, value: s.lockout_threshold });
    const lockMin = input({ type: 'number', min: 1, max: 1440, value: s.lockout_minutes });
    const days = input({ type: 'number', min: 1, max: 90, value: s.session_days });
    const guide = h('textarea', { class: 'input', rows: 12, value: s.guidelines });
    main.append(head('セキュリティ・規程', '企業全体のパスワード規則・ロック・利用ガイドラインを設定します。'), err,
      h('section', { class: 'card section' }, h('h2', null, 'パスワード'),
        h('div', { class: 'grid-2' },
          field('最小文字数', minLen, '8〜64文字。英字と数字は常に必須です。'),
          field('仮パスワードの有効期限（時間）', ttl, '発行してからこの時間を過ぎると、仮パスワードではログインできません。')),
        h('label', { class: 'check' }, sym, '記号（!#$% など）を必須にする（オフでも記号は使えます）')),
      h('section', { class: 'card section' }, h('h2', null, 'ログイン'),
        h('div', { class: 'grid-2' },
          field('ロックするまでの失敗回数', lockN), field('ロックする時間（分）', lockMin)),
        field('ログイン状態を保つ日数', days, '過ぎると再ログインが必要です。変更は次回のログインから反映されます。')),
      h('section', { class: 'card section' }, h('h2', null, '社内SNS 利用ガイドライン'),
        h('p', { class: 'small muted' }, '内容を変更すると、全員が次にアプリを開いたときに再度同意を求められます（現在 第' + s.guidelines_version + '版）。'),
        guide),
      h('div', { class: 'toolbar' }, h('button', { class: 'btn primary', type: 'button', onclick: async function () {
        err.classList.add('hidden');
        try {
          await api('PATCH', '/api/admin/settings', {
            password_min_length: Number(minLen.value), password_require_symbol: sym.checked,
            temp_password_ttl_hours: Number(ttl.value), lockout_threshold: Number(lockN.value),
            lockout_minutes: Number(lockMin.value), session_days: Number(days.value), guidelines: guide.value,
          });
          toast('保存しました');
          renderShell();
        } catch (e) { showError(err, e); window.scrollTo(0, 0); }
      } }, '保存')));
  }

  // ------------------------------------------------------------ メール
  async function viewMail() {
    const data = await api('GET', '/api/admin/mail');
    main.append(head('メール送信履歴', '管理コンソールから送ったメールの記録です。'));
    if (data.mail_mode !== 'smtp') {
      main.append(h('div', { class: 'alert warn' }, '開発モード：実際には送信していません。確認用に本文（仮パスワードを含む）を表示しています。本番（SMTP）では本文の仮パスワードは伏せて記録されます。'));
    }
    if (!data.messages.length) { main.append(h('div', { class: 'card empty' }, '送信したメールはありません')); return; }
    const box = h('div', { class: 'card section' });
    data.messages.forEach(function (m) {
      const st = { outbox: ['未送信（開発）', 'warn'], sent: ['送信済み', 'ok'], failed: ['失敗', 'danger'] }[m.status] || [m.status, ''];
      box.append(h('details', { class: 'mail-item' },
        h('summary', null, h('span', { class: 'badge ' + st[1] }, st[0]), ' ', m.subject, h('span', { class: 'small muted' }, '　' + m.to + '・' + fmt(m.created_at))),
        h('div', { class: 'mail-body' }, m.body), m.error ? h('div', { class: 'alert error' }, m.error) : null));
    });
    main.append(box);
  }

  // ------------------------------------------------------------ 自分のアカウント
  async function viewAccount() {
    const data = await api('GET', '/api/me/passkeys');
    const err = errorBox();
    main.append(head('自分のアカウント', S.me.display_name + '（' + S.me.employee_code + '）'), err);
    const list = h('div');
    if (!data.passkeys.length) list.append(h('p', { class: 'muted' }, 'パスキーは登録されていません。'));
    data.passkeys.forEach(function (p) {
      list.append(h('div', { class: 'list-item' },
        h('div', null, h('strong', null, p.name), h('div', { class: 'small muted' }, '登録 ' + fmt(p.created_at) + '・最終使用 ' + fmt(p.last_used_at))),
        h('button', { class: 'btn small danger', type: 'button', onclick: async function () {
          try { await api('DELETE', '/api/me/passkeys/' + p.id); toast('削除しました'); renderShell(); } catch (e) { showError(err, e); }
        } }, '削除')));
    });
    const nameInput = input({ placeholder: '例：会社の MacBook', maxlength: 40 });
    const reg = h('button', { class: 'btn primary', type: 'button', disabled: !TsunaguPasskey.supported() }, 'このブラウザでパスキーを登録');
    reg.addEventListener('click', async function () {
      reg.disabled = true;
      try {
        await TsunaguPasskey.register({ token: S.token, name: nameInput.value.trim() || 'ブラウザ' });
        toast('パスキーを登録しました');
        renderShell();
      } catch (e) { showError(err, new Error(TsunaguPasskey.friendlyError(e))); reg.disabled = false; }
    });
    main.append(h('section', { class: 'card section' }, h('h2', null, 'パスキー'), list,
      h('div', { class: 'toolbar' }, nameInput, reg)));

    const cur = input({ type: 'password', autocomplete: 'current-password' });
    const nxt = input({ type: 'password', autocomplete: 'new-password' });
    main.append(h('section', { class: 'card section' }, h('h2', null, 'パスワードの変更'),
      h('div', { class: 'grid-2' }, field('現在のパスワード', cur), field('新しいパスワード', nxt, '変更すると、他の端末はすべてログアウトされます。')),
      h('button', { class: 'btn', type: 'button', onclick: async function () {
        err.classList.add('hidden');
        try {
          const d = await api('POST', '/api/auth/change-password', { current_password: cur.value, new_password: nxt.value });
          setToken(d.token);
          toast('パスワードを変更しました');
          renderShell();
        } catch (e) { showError(err, e); window.scrollTo(0, 0); }
      } }, '変更する')));
  }

  // ------------------------------------------------------------ 起動
  async function boot() {
    if (!S.token) { renderLogin(); return; }
    try {
      const data = await api('GET', '/api/me', undefined, { quiet401: true });
      S.me = data.user;
      S.company = data.company;
      if (S.me.must_change_password) { renderPasswordChange(); return; }
      if (S.me.role !== 'admin') { setToken(null); renderLogin('管理者の権限がないアカウントです。'); return; }
      renderShell();
    } catch (e) {
      setToken(null);
      renderLogin();
    }
  }
  boot();
})();
