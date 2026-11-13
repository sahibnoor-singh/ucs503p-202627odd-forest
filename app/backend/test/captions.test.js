const { test } = require('node:test');
const assert = require('node:assert/strict');
const { startServer, addUser, videoForm } = require('./helpers');
const { sanitizeCaptions } = require('../src/services/geminiService');

const WITH_CAPTIONS = {
  transcript: 'namaste dosto', detectedStance: 'FOR', overallSummary: 's', claims: [],
  captions: [{ start: 0, end: 1.5, text: 'namaste' }, { start: 1.5, end: 3, text: 'dosto' }]
};

test('sanitizeCaptions keeps good lines, sorts them, removes overlaps and drops junk', () => {
  const out = sanitizeCaptions([
    { start: 5, end: 7, text: '  hello   world ' },
    { start: 0, end: 2.5, text: 'first' },
    { start: 'x', end: 3, text: 'not a number' },
    { start: 2, end: 9, text: 'overlaps the next line' },
    { start: 20, end: 20, text: 'no end time' },
    { start: 30, end: 31, text: '   ' },
    { start: -4, end: 1, text: 'before the video' },
    null,
    'text'
  ]);
  assert.deepEqual(out, [
    { start: 0, end: 2, text: 'first' },
    { start: 2, end: 5, text: 'overlaps the next line' },
    { start: 5, end: 7, text: 'hello world' },
    { start: 20, end: 22, text: 'no end time' }
  ]);
  assert.deepEqual(sanitizeCaptions(undefined), []);
  assert.deepEqual(sanitizeCaptions('nope'), []);
  assert.equal(sanitizeCaptions(Array.from({ length: 2000 }, (_, i) => ({ start: i, end: i + 1, text: 'x' }))).length, 600);
  assert.equal(sanitizeCaptions([{ start: 0, end: 1, text: 'a'.repeat(500) }])[0].text.length, 160);
});

test('a video with captions says so, and /captions returns them; a video without speech returns an empty list', async () => {
  let n = 0;
  const s = await startServer({
    analyzer: { analyzeAudio: async () => (n++ === 0 ? WITH_CAPTIONS : { ...WITH_CAPTIONS, captions: [] }) }
  });
  try {
    addUser(s.db, 'u');
    const a = await s.api('POST', '/api/posts', { user: 'u', form: videoForm({ kind: 'VIDEO', title: 'with speech' }) });
    await s.idle();
    const b = await s.api('POST', '/api/posts', { user: 'u', form: videoForm({ kind: 'VIDEO', title: 'silent' }) });
    await s.idle();

    const detail = await s.api('GET', `/api/posts/${a.data.post.id}`, { user: 'u' });
    assert.equal(detail.data.post.hasCaptions, true);
    const caps = await s.api('GET', `/api/posts/${a.data.post.id}/captions`, { user: 'u' });
    assert.equal(caps.status, 200);
    assert.deepEqual(caps.data.captions, WITH_CAPTIONS.captions);

    const silent = await s.api('GET', `/api/posts/${b.data.post.id}`, { user: 'u' });
    assert.equal(silent.data.post.hasCaptions, false);
    const none = await s.api('GET', `/api/posts/${b.data.post.id}/captions`, { user: 'u' });
    assert.deepEqual(none.data.captions, []);
  } finally { await s.close(); }
});

test('captions of an unfinished video are only for its author, and an unknown post is a 404', async () => {
  let release; const gate = new Promise((r) => { release = r; });
  const s = await startServer({ analyzer: { analyzeAudio: async () => { await gate; return WITH_CAPTIONS; } } });
  try {
    addUser(s.db, 'u'); addUser(s.db, 'other');
    const a = await s.api('POST', '/api/posts', { user: 'u', form: videoForm({ kind: 'VIDEO', title: 't' }) });
    assert.equal((await s.api('GET', `/api/posts/${a.data.post.id}/captions`, { user: 'other' })).status, 404);
    assert.equal((await s.api('GET', `/api/posts/${a.data.post.id}/captions`, { user: 'u' })).status, 200);
    assert.equal((await s.api('GET', '/api/posts/does-not-exist/captions', { user: 'u' })).status, 404);
    release();
    await s.idle();
  } finally { await s.close(); }
});

// ---------- description, English captions, other languages ----------

const HINDI = {
  transcript: 'namaste dosto', detectedStance: 'FOR', overallSummary: 'Greets the viewers.', claims: [],
  language: 'hi', captions: [{ start: 0, end: 1.5, text: 'नमस्ते' }, { start: 1.5, end: 3, text: 'दोस्तो' }]
};
// a translator that tags each line with the language, and counts how often it is called
function fakeTranslator(calls, { fail = false } = {}) {
  return async (cues, lang) => {
    calls.push(lang);
    await new Promise((r) => setTimeout(r, 20));
    return fail ? null : cues.map((c) => ({ ...c, text: `[${lang}] ${c.text}` }));
  };
}

test('a video gets its heading and description from the analysis, but what the author wrote is kept', async () => {
  const s = await startServer({
    analyzer: {
      analyzeAudio: async () => HINDI,
      describePost: async ({ isRoot, parentContext }) => ({ title: isRoot ? 'Is this a good greeting?' : null, body: parentContext ? 'A reply caption.' : 'A root caption.' })
    }
  });
  try {
    addUser(s.db, 'u');
    const root = await s.api('POST', '/api/posts', { user: 'u', form: videoForm({ kind: 'VIDEO' }) });
    const own = await s.api('POST', '/api/posts', { user: 'u', form: videoForm({ kind: 'VIDEO', title: 'My own title', body: 'My own words' }) });
    await s.idle();
    const reply = await s.api('POST', '/api/posts', { user: 'u', form: videoForm({ kind: 'VIDEO', parentId: root.data.post.id }) });
    await s.idle();

    const r = (await s.api('GET', `/api/posts/${root.data.post.id}`, { user: 'u' })).data.post;
    assert.equal(r.title, 'Is this a good greeting?');
    assert.equal(r.body, 'A root caption.');
    const o = (await s.api('GET', `/api/posts/${own.data.post.id}`, { user: 'u' })).data.post;
    assert.equal(o.title, 'My own title');
    assert.equal(o.body, 'My own words');
    const p = (await s.api('GET', `/api/posts/${reply.data.post.id}`, { user: 'u' })).data.post;
    assert.equal(p.title, null, 'replies have no heading');
    assert.equal(p.body, 'A reply caption.');
  } finally { await s.close(); }
});

test('a failing description step does not fail the post', async () => {
  const s = await startServer({
    analyzer: { analyzeAudio: async () => HINDI, describePost: async () => { throw new Error('boom'); }, translateCaptions: async () => { throw new Error('boom'); } }
  });
  try {
    addUser(s.db, 'u');
    const res = await s.api('POST', '/api/posts', { user: 'u', form: videoForm({ kind: 'VIDEO', title: 't' }) });
    await s.idle();
    const post = (await s.api('GET', `/api/posts/${res.data.post.id}`, { user: 'u' })).data.post;
    assert.equal(post.status, 'READY');
    assert.equal(post.title, 't');
  } finally { await s.close(); }
});

test('captions come back in the spoken language, in English (made up front), and other languages on request', async () => {
  const calls = [];
  const s = await startServer({ analyzer: { analyzeAudio: async () => HINDI, translateCaptions: fakeTranslator(calls) } });
  try {
    addUser(s.db, 'u');
    const res = await s.api('POST', '/api/posts', { user: 'u', form: videoForm({ kind: 'VIDEO', title: 't' }) });
    await s.idle();
    const id = res.data.post.id;
    assert.deepEqual(calls, ['en'], 'English is made while the video is analysed');

    const orig = (await s.api('GET', `/api/posts/${id}/captions`, { user: 'u' })).data;
    assert.equal(orig.language, 'hi');
    assert.equal(orig.lang, 'original');
    assert.equal(orig.captions[0].text, 'नमस्ते');
    assert.ok(orig.languages.some((l) => l.code === 'pa' && l.name === 'Punjabi'));

    const same = (await s.api('GET', `/api/posts/${id}/captions?lang=hi`, { user: 'u' })).data;
    assert.equal(same.captions[0].text, 'नमस्ते', 'asking for the spoken language gives the original');

    const en = (await s.api('GET', `/api/posts/${id}/captions?lang=en`, { user: 'u' })).data;
    assert.equal(en.lang, 'en');
    assert.equal(en.captions[0].text, '[en] नमस्ते');
    assert.deepEqual(calls, ['en'], 'English was already stored, nothing more was translated');

    // Punjabi: translated on the first request (two at once cost one translation), then kept
    const [a, b] = await Promise.all([
      s.api('GET', `/api/posts/${id}/captions?lang=pa`, { user: 'u' }),
      s.api('GET', `/api/posts/${id}/captions?lang=pa`, { user: 'u' })
    ]);
    assert.equal(a.data.captions[1].text, '[pa] दोस्तो');
    assert.deepEqual(b.data.captions, a.data.captions);
    await s.api('GET', `/api/posts/${id}/captions?lang=pa`, { user: 'u' });
    assert.deepEqual(calls, ['en', 'pa']);

    assert.equal((await s.api('GET', `/api/posts/${id}/captions?lang=xx`, { user: 'u' })).status, 400);
  } finally { await s.close(); }
});

test('a translation that fails is a 503 and is tried again next time; a video already in English needs no English track', async () => {
  const calls = [];
  let fail = true;
  const s = await startServer({
    analyzer: {
      analyzeAudio: async () => ({ ...HINDI }),
      translateCaptions: async (cues, lang) => { calls.push(lang); return fail && lang !== 'en' ? null : cues.map((c) => ({ ...c, text: `[${lang}] ${c.text}` })); }
    }
  });
  try {
    addUser(s.db, 'u');
    const res = await s.api('POST', '/api/posts', { user: 'u', form: videoForm({ kind: 'VIDEO', title: 't' }) });
    await s.idle();
    const id = res.data.post.id;
    assert.equal((await s.api('GET', `/api/posts/${id}/captions?lang=ta`, { user: 'u' })).status, 503);
    fail = false;
    const ok = await s.api('GET', `/api/posts/${id}/captions?lang=ta`, { user: 'u' });
    assert.equal(ok.status, 200);
    assert.equal(ok.data.captions[0].text, '[ta] नमस्ते');
  } finally { await s.close(); }

  const english = [];
  const s2 = await startServer({
    analyzer: { analyzeAudio: async () => ({ ...HINDI, language: 'en' }), translateCaptions: fakeTranslator(english) }
  });
  try {
    addUser(s2.db, 'u');
    await s2.api('POST', '/api/posts', { user: 'u', form: videoForm({ kind: 'VIDEO', title: 't' }) });
    await s2.idle();
    assert.deepEqual(english, [], 'spoken English needs no English track');
  } finally { await s2.close(); }
});
