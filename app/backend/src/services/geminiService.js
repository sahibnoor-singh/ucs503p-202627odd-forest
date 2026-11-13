const { GoogleGenAI } = require('@google/genai');
const fs = require('fs');

/**
 * Extracts list of available Gemini API keys from environment variables.
 * Supports comma-separated keys in GEMINI_API_KEYS, single GEMINI_API_KEY,
 * as well as numbered keys (GEMINI_KEY_1, GEMINI_KEY_2, GEMINI_API_KEY_1, etc.).
 */
function getApiKeys() {
  const keys = [];
  const rawList = process.env.GEMINI_API_KEYS || '';
  if (rawList.trim()) {
    rawList.split(',').forEach(k => {
      const clean = k.trim();
      if (clean && !keys.includes(clean)) keys.push(clean);
    });
  }

  const envNames = [
    'GEMINI_API_KEY',
    'GEMINI_KEY_1',
    'GEMINI_KEY_2',
    'GEMINI_KEY_3',
    'GEMINI_API_KEY_1',
    'GEMINI_API_KEY_2',
    'GEMINI_API_KEY_3'
  ];

  envNames.forEach(name => {
    if (process.env[name]) {
      const val = process.env[name].trim();
      if (val && !keys.includes(val)) keys.push(val);
    }
  });

  return keys.length > 0 ? keys : [process.env.GEMINI_API_KEY || null];
}

// Models in optimal fallback order prioritizing gemini-3.6-flash & high daily quotas (500 RPD)
const MODELS_TO_TRY = [
  'gemini-3.6-flash',      // Primary active model
  'gemini-3.5-flash-lite', // 500 RPD, 15 RPM
  'gemini-3.1-flash-lite', // 500 RPD, 15 RPM
  'gemini-2.5-flash-lite', // 20 RPD, 10 RPM
  'gemini-2.5-flash',      // 20 RPD, 5 RPM
  'gemini-3.5-flash',      // 20 RPD, 5 RPM
  'gemini-3.7-flash',      // 20 RPD, 5 RPM
  'gemini-3.8-flash',      // 20 RPD, 5 RPM
  'gemini-3-flash',        // 20 RPD, 5 RPM
  'gemini-2.0-flash',      // Standard 2.0 Flash
  'gemini-2.0-flash-lite', // Standard 2.0 Lite
  'gemini-1.5-flash',      // Standard 1.5 Flash
  'gemini-1.5-flash-8b',   // 1.5 8B
  'gemini-1.5-pro'         // 1.5 Pro
];

function hasApiKeys() {
  return getApiKeys().some(Boolean);
}

const CAPTIONS_SCHEMA = {
  type: 'array',
  description: 'Subtitle lines covering all the speech, in order, timed in seconds from the start of the audio.',
  items: {
    type: 'object',
    properties: {
      start: { type: 'number', description: 'Seconds from the start of the audio when this line starts being spoken.' },
      end: { type: 'number', description: 'Seconds from the start of the audio when this line has been spoken.' },
      text: { type: 'string', description: 'The words spoken in this line, in the original spoken language and script.' }
    },
    required: ['start', 'end', 'text']
  }
};

const CAPTION_RULES =
  'Split everything that is spoken into short subtitle lines, in order, with start and end times in seconds measured ' +
  'from the very start of the audio (for example 12.4, not 0:12). Each line is at most 8 words and at most 4 seconds, ' +
  'in the original spoken language and script (Hindi stays Hindi, not translated). Lines must not overlap. ' +
  'Leave out silence and music. If nobody speaks, return an empty list.';

/** Languages a caption track can be shown in besides the spoken one (ISO 639-1 codes). */
const CAPTION_LANGUAGES = [
  { code: 'en', name: 'English', native: 'English' },
  { code: 'hi', name: 'Hindi', native: 'हिन्दी' },
  { code: 'pa', name: 'Punjabi', native: 'ਪੰਜਾਬੀ' },
  { code: 'bn', name: 'Bengali', native: 'বাংলা' },
  { code: 'ta', name: 'Tamil', native: 'தமிழ்' },
  { code: 'te', name: 'Telugu', native: 'తెలుగు' },
  { code: 'mr', name: 'Marathi', native: 'मराठी' },
  { code: 'gu', name: 'Gujarati', native: 'ગુજરાતી' }
];

/** A two or three letter lower-case language code, or null. */
function normalizeLanguage(code) {
  const c = String(code == null ? '' : code).trim().toLowerCase();
  return /^[a-z]{2,3}$/.test(c) ? c : null;
}

const MAX_CAPTIONS = 600;
const MAX_CAPTION_SECONDS = 3600;

/**
 * Cleans the captions a model sent: only finite numbers, sorted, no overlaps, no empty or huge lines.
 * Returns [{ start, end, text }] with times rounded to 10 ms. Anything unusable gives [].
 */
function sanitizeCaptions(raw) {
  if (!Array.isArray(raw)) return [];
  const cues = [];
  for (const c of raw) {
    if (!c || typeof c !== 'object') continue;
    const start = Number(c.start);
    let end = Number(c.end);
    const text = String(c.text == null ? '' : c.text).replace(/\s+/g, ' ').trim().slice(0, 160);
    if (!text || !Number.isFinite(start) || !Number.isFinite(end)) continue;
    if (start < 0 || start > MAX_CAPTION_SECONDS) continue;
    if (end <= start) end = start + 2; // a missing end: show it for two seconds
    cues.push({ start, end: Math.min(end, MAX_CAPTION_SECONDS), text });
  }
  cues.sort((a, b) => a.start - b.start);
  const out = [];
  for (let i = 0; i < cues.length && out.length < MAX_CAPTIONS; i++) {
    const next = cues[i + 1];
    const end = next && cues[i].end > next.start ? next.start : cues[i].end; // no overlap
    if (end - cues[i].start < 0.2) continue;
    out.push({ start: Math.round(cues[i].start * 100) / 100, end: Math.round(end * 100) / 100, text: cues[i].text });
  }
  return out;
}

/** Stance values we store for replies. Gemini may also say EVIDENCE/PARENT; both map to UNRESOLVED. */
function normalizeStance(stance) {
  const s = String(stance || '').toUpperCase();
  return s === 'FOR' || s === 'AGAINST' ? s : 'UNRESOLVED';
}

function offlineAnalysis(parentContext) {
  return {
    transcript: 'Transcription unavailable (no Gemini key or quota reached).',
    detectedStance: parentContext ? 'UNRESOLVED' : 'PARENT',
    overallSummary: 'Video added to the debate. AI analysis was not available, so it has no summary or fact-check yet.',
    claims: [],
    captions: [],
    language: null,
    _modelUsed: 'offline-fallback'
  };
}

/**
 * Analyzes audio natively using Gemini AI:
 * 1. Generates full speech transcription.
 * 2. If parent context is present, automatically detects debate stance (FOR, AGAINST, UNRESOLVED, EVIDENCE).
 * 3. Extracts key claims/statements and performs factual credibility checking (True, False, Misleading, Opinion).
 * 
 * Implements intelligent multi-model & multi-key fallback cascade across:
 * - gemini-2.0-flash
 * - gemini-1.5-flash
 * - gemini-1.5-flash-8b
 * - gemini-2.0-flash-lite
 * - gemini-1.5-pro
 * 
 * @param {string} audioPath - Absolute path to the audio file (.mp3 / .wav).
 * @param {string|null} parentContext - Optional transcript or topic of the parent video being replied to.
 * @returns {Promise<Object>} - Structured JSON: { transcript, detectedStance, overallSummary, claims }
 */
async function analyzeAudio(audioPath, parentContext = null) {
  if (!hasApiKeys()) {
    console.warn('[Gemini Pipeline] No Gemini API key configured. Using offline fallback.');
    return offlineAnalysis(parentContext);
  }
  console.log(`[Gemini Pipeline] Reading audio for analysis: ${audioPath}`);

  const audioData = fs.readFileSync(audioPath);
  const audioBase64 = audioData.toString('base64');
  const audioSizeKb = (audioData.length / 1024).toFixed(1);

  console.log(`[Gemini Pipeline] Audio file size: ${audioSizeKb} KB`);

  const responseSchema = {
    type: 'object',
    properties: {
      transcript: {
        type: 'string',
        description: 'The full spoken transcript of the audio in its original spoken language.'
      },
      detectedStance: {
        type: 'string',
        enum: ['PARENT', 'FOR', 'AGAINST', 'UNRESOLVED', 'EVIDENCE'],
        description: 'Automatically classified stance towards parent video: FOR (supports/agrees), AGAINST (rebuttal/disagrees), UNRESOLVED (neutral/ambiguous), or EVIDENCE (factual extension).'
      },
      overallSummary: {
        type: 'string',
        description: 'A brief 2-3 sentence overview of the discussion and overall factual credibility of the video.'
      },
      claims: {
        type: 'array',
        description: 'List of main claims and statements evaluated for factual credibility.',
        items: {
          type: 'object',
          properties: {
            claim: {
              type: 'string',
              description: 'The extracted statement or factual claim made in the video.'
            },
            verdict: {
              type: 'string',
              enum: ['TRUE', 'MOSTLY_TRUE', 'PARTIALLY_TRUE', 'FALSE', 'MISLEADING', 'UNVERIFIED_OPINION'],
              description: 'Factual verification status: TRUE, MOSTLY_TRUE, PARTIALLY_TRUE, FALSE, MISLEADING, or UNVERIFIED_OPINION.'
            },
            credibilityScore: {
              type: 'number',
              description: 'Credibility score from 0.0 (completely false/debunked) to 1.0 (completely verified/true).'
            },
            explanation: {
              type: 'string',
              description: 'Clear fact-check explanation analyzing why this statement is true, false, misleading, or an unverifiable opinion.'
            },
            evidence: {
              type: 'string',
              description: 'Factual evidence, official data, or context used to verify or refute this claim.'
            }
          },
          required: ['claim', 'verdict', 'credibilityScore', 'explanation', 'evidence']
        }
      },
      captions: CAPTIONS_SCHEMA,
      language: {
        type: 'string',
        description: 'ISO 639-1 code of the main language spoken in the audio, for example hi, en, pa. Hinglish (Hindi in Latin letters) is hi.'
      }
    },
    required: ['transcript', 'detectedStance', 'overallSummary', 'claims']
  };

  let promptText = `Listen to this audio carefully and perform speech transcription, automated debate stance classification, and factual credibility verification:\n\n`;

  promptText += `1. TRANSCRIPT: Provide the exact and FULL spoken transcript of everything said in the audio (preserving the original language, e.g. Hindi, English, Punjabi, etc.).\n`;

  if (parentContext && parentContext.trim().length > 0) {
    promptText += `2. AUTOMATIC STANCE CLASSIFICATION:\n`;
    promptText += `This audio is a direct response to the following PARENT discussion:\n`;
    promptText += `"""\n${parentContext.trim()}\n"""\n`;
    promptText += `Analyze the relationship between this response and the parent discussion, and classify the stance as:\n`;
    promptText += `   - 'FOR': If the response supports, agrees with, or defends the parent argument.\n`;
    promptText += `   - 'AGAINST': If the response directly opposes, refutes, challenges, or criticizes the parent argument.\n`;
    promptText += `   - 'UNRESOLVED': If the stance is mixed, neutral, sarcastic, or ambiguous.\n`;
    promptText += `   - 'EVIDENCE': If the response mainly provides statistical data, study results, or legal context to extend the debate.\n`;
  } else {
    promptText += `2. STANCE: Set detectedStance to 'PARENT' since this is a root parent video.\n`;
  }

  promptText += `3. OVERALL SUMMARY: Provide a concise summary of the topic and the overall factual reliability of the statements.\n`;
  promptText += `4. FACT-CHECKING & CREDIBILITY: Identify the key claims/statements made by the speaker and evaluate their truthfulness:\n`;
  promptText += `   - VERDICT: Choose one of [TRUE, MOSTLY_TRUE, PARTIALLY_TRUE, FALSE, MISLEADING, UNVERIFIED_OPINION].\n`;
  promptText += `   - CREDIBILITY SCORE: Rate from 0.0 to 1.0.\n`;
  promptText += `   - EXPLANATION: Explain objectively why the statement is factually correct, distorted, fabricated, or a subjective personal opinion.\n`;
  promptText += `   - EVIDENCE: Cite real-world facts, statistics, or historical records that support or disprove the claim.\n\n`;
  promptText += `5. CAPTIONS: ${CAPTION_RULES}\n`;
  promptText += `6. LANGUAGE: Set language to the ISO 639-1 code of the main language spoken (hi, en, pa, ...).\n\n`;
  promptText += `Return your response in strict accordance with the JSON schema.`;

  const modelsToTry = MODELS_TO_TRY;

  const apiKeys = getApiKeys();
  let lastError = null;

  for (let keyIdx = 0; keyIdx < apiKeys.length; keyIdx++) {
    const activeKey = apiKeys[keyIdx];
    const aiClient = new GoogleGenAI({
      apiKey: activeKey || process.env.GEMINI_API_KEY
    });

    for (const modelName of modelsToTry) {
      try {
        console.log(`[Gemini Pipeline] Attempting analysis using model: ${modelName} (Key ${keyIdx + 1}/${apiKeys.length})...`);
        
        const response = await aiClient.models.generateContent({
          model: modelName,
          contents: [
            {
              role: 'user',
              parts: [
                {
                  inlineData: {
                    mimeType: 'audio/mp3',
                    data: audioBase64
                  }
                },
                {
                  text: promptText
                }
              ]
            }
          ],
          config: {
            responseMimeType: 'application/json',
            responseSchema: responseSchema
          }
        });

        if (response && response.text) {
          console.log(`[Gemini Pipeline] Successfully received structured analysis from ${modelName}!`);
          
          let cleanedText = response.text.trim();
          if (cleanedText.startsWith('```json')) {
            cleanedText = cleanedText.replace(/^```json\s*/, '').replace(/```\s*$/, '');
          } else if (cleanedText.startsWith('```')) {
            cleanedText = cleanedText.replace(/^```\s*/, '').replace(/```\s*$/, '');
          }

          const parsedResult = JSON.parse(cleanedText);
          parsedResult._modelUsed = modelName;
          parsedResult.captions = sanitizeCaptions(parsedResult.captions);
          parsedResult.language = normalizeLanguage(parsedResult.language);
          return parsedResult;
        }
      } catch (err) {
        console.warn(`[Gemini Pipeline] Model ${modelName} (Key ${keyIdx + 1}) encountered issue: ${err.message}`);
        lastError = err;
        // Continue to next model or next key in cascade
      }
    }
  }

  // Graceful Fallback if all Gemini models & keys hit quota limits
  console.error(`[Gemini Pipeline] All Gemini models/keys exhausted or offline. Reason: ${lastError ? lastError.message : 'Unknown'}. Returning fallback structure.`);
  return offlineAnalysis(parentContext);
}

// Text-only calls (titles, descriptions, translations) go to the first few models of the cascade.
const TEXT_MODELS = MODELS_TO_TRY.slice(0, 6);

/** One structured Gemini call over every key and model in turn. Resolves to the parsed JSON, or null when nothing worked. */
async function generateStructured({ prompt, schema, label }) {
  if (!hasApiKeys()) return null;
  for (const apiKey of getApiKeys().filter(Boolean)) {
    const client = new GoogleGenAI({ apiKey });
    for (const model of TEXT_MODELS) {
      try {
        const response = await client.models.generateContent({
          model,
          contents: [{ role: 'user', parts: [{ text: prompt }] }],
          config: { responseMimeType: 'application/json', responseSchema: schema }
        });
        if (response && response.text) return JSON.parse(response.text.trim());
      } catch (err) {
        console.warn(`[Gemini ${label}] ${model} failed: ${String(err.message).slice(0, 120)}`);
      }
    }
  }
  return null;
}

const oneLine = (v, max) => String(v == null ? '' : v).replace(/\s+/g, ' ').replace(/^["'“”]+|["'“”]+$/g, '').trim().slice(0, max);

/**
 * Translates caption lines into [langCode] (one of CAPTION_LANGUAGES), keeping their timing.
 * Resolves to [{ start, end, text }] with the same number of lines, or null when it could not be done. Never throws.
 */
async function translateCaptions(cues, langCode) {
  const lang = CAPTION_LANGUAGES.find((l) => l.code === langCode);
  if (!lang || !Array.isArray(cues) || !cues.length) return null;
  const lines = cues.map((c) => c.text);
  const prompt =
    `Translate these subtitle lines into ${lang.name} (${lang.native}). Keep the meaning and the tone, keep each line short enough ` +
    `to read in a couple of seconds, do not merge or split lines, keep names as they are, and use the normal script of ${lang.name}. ` +
    `Return JSON {"lines": [...]} with exactly ${lines.length} strings, in the same order.\n\n${JSON.stringify(lines)}`;
  const schema = { type: 'object', properties: { lines: { type: 'array', items: { type: 'string' } } }, required: ['lines'] };
  for (let attempt = 0; attempt < 2; attempt++) {
    const out = await generateStructured({ prompt, schema, label: 'Translate' });
    if (out && Array.isArray(out.lines) && out.lines.length === lines.length) {
      return cues.map((c, i) => ({ start: c.start, end: c.end, text: oneLine(out.lines[i], 200) || c.text }));
    }
  }
  return null;
}

/**
 * Writes the post's heading and description from what is said in the video (never from anything else).
 *   root video  -> { title: a specific debate question, body: 1-2 sentence description }
 *   reply video -> { title: null, body: 1-2 sentence description of the point it makes }
 * Resolves to null when there is nothing to work from or no model answered. Never throws.
 */
async function describePost({ transcript, summary, parentContext = null, isRoot = true }) {
  const spoken = String(transcript || '').trim();
  // Nothing (or next to nothing) was said or written: a heading made from the AI's note that there was no speech would be nonsense
  if (spoken.length < 12) return null;
  let prompt =
    'Someone posted a short video on FOREST, a political debate app where every post is a video opinion and replies are videos.\n\n' +
    `WHAT THEY SAY (transcript, may be Hindi, Hinglish or English):\n"""\n${spoken.slice(0, 4000)}\n"""\n\n` +
    (summary ? `AI SUMMARY OF IT: ${String(summary).slice(0, 600)}\n\n` : '') +
    (parentContext ? `THIS VIDEO IS A REPLY TO:\n"""\n${String(parentContext).slice(0, 1500)}\n"""\n\n` : '') +
    'Write in English, using only what is said above (never invent facts, names or numbers).\n';
  if (isRoot) {
    prompt += '1. title: ONE debate question (max 90 characters, ends with ?) that the speaker\'s main claim answers. Be specific: name the ' +
      'person, event or policy the speaker is really talking about. Never a generic question.\n';
  }
  prompt += `${isRoot ? '2' : '1'}. description: the caption of this post, 1-2 plain sentences (max 220 characters) saying what the speaker argues and the ` +
    'key point or fact they use. No hashtags, no emoji, no "the speaker" filler when you can say who or what.';
  const schema = {
    type: 'object',
    properties: { title: { type: 'string' }, description: { type: 'string' } },
    required: isRoot ? ['title', 'description'] : ['description']
  };
  const out = await generateStructured({ prompt, schema, label: 'Describe' });
  if (!out) return null;
  const body = oneLine(out.description, 280);
  const title = isRoot ? oneLine(out.title, 120) : '';
  if (!body && !title) return null;
  return { title: title || null, body: body || null };
}

/**
 * Captions only (no stance, no fact-check): for videos that were analysed before captions existed.
 * Same key / model cascade as analyzeAudio. Never throws; resolves to [] when nothing could be produced.
 * @param {string} audioPath - Absolute path to the audio file (.mp3).
 */
async function transcribeCaptions(audioPath) {
  if (!hasApiKeys()) return [];
  const data = fs.readFileSync(audioPath).toString('base64');
  const prompt = `Listen to this audio and write subtitles. ${CAPTION_RULES} Return JSON {"captions": [...]}.`;
  const schema = { type: 'object', properties: { captions: CAPTIONS_SCHEMA }, required: ['captions'] };
  for (const apiKey of getApiKeys().filter(Boolean)) {
    const client = new GoogleGenAI({ apiKey });
    for (const model of MODELS_TO_TRY) {
      try {
        const response = await client.models.generateContent({
          model,
          contents: [{ role: 'user', parts: [{ inlineData: { mimeType: 'audio/mp3', data } }, { text: prompt }] }],
          config: { responseMimeType: 'application/json', responseSchema: schema }
        });
        if (response && response.text) return sanitizeCaptions(JSON.parse(response.text.trim()).captions);
      } catch (err) {
        console.warn(`[Gemini Captions] ${model} failed: ${err.message}`);
      }
    }
  }
  return [];
}

/**
 * Classifies a short TEXT reply against the thing it replies to.
 * Resolves to 'FOR' | 'AGAINST' | 'UNRESOLVED'. Never throws: with no key, on
 * errors, or when every model fails it resolves to 'UNRESOLVED'.
 * @param {string} text - The reply text (max 280 chars is enforced by the route).
 * @param {string|null} parentContext - Transcript/summary/text of the parent.
 */
async function classifyReplyText(text, parentContext = null) {
  if (!hasApiKeys() || !parentContext) return 'UNRESOLVED';

  const prompt =
    `A user wrote a short reply in a debate app.\n\nPARENT:\n"""\n${String(parentContext).slice(0, 2000)}\n"""\n\n` +
    `REPLY:\n"""\n${text}\n"""\n\n` +
    `Classify the reply's stance toward the parent: FOR (supports/agrees), AGAINST (opposes/refutes), ` +
    `or UNRESOLVED (neutral, mixed, sarcastic or unclear). Answer with JSON {"stance": "..."}.`;

  // Cheapest/highest-quota models first; text needs far less than audio does.
  const models = ['gemini-3.6-flash', 'gemini-3.5-flash-lite', 'gemini-3.1-flash-lite', 'gemini-2.0-flash'];
  for (const apiKey of getApiKeys().filter(Boolean)) {
    const client = new GoogleGenAI({ apiKey });
    for (const model of models) {
      try {
        const response = await client.models.generateContent({
          model,
          contents: [{ role: 'user', parts: [{ text: prompt }] }],
          config: {
            responseMimeType: 'application/json',
            responseSchema: {
              type: 'object',
              properties: { stance: { type: 'string', enum: ['FOR', 'AGAINST', 'UNRESOLVED'] } },
              required: ['stance']
            }
          }
        });
        if (response && response.text) return normalizeStance(JSON.parse(response.text.trim()).stance);
      } catch (err) {
        console.warn(`[Gemini Text] ${model} failed: ${err.message}`);
      }
    }
  }
  return 'UNRESOLVED';
}

/**
 * Generates a concise personality summary from self-described keywords using Gemini.
 * @param {string[]} keywords
 * @returns {Promise<string|null>}
 */
async function generatePersonalitySummary(keywords) {
  if (!hasApiKeys()) return null;
  const kw = Array.isArray(keywords) ? keywords.join(', ') : String(keywords || '');
  const prompt =
    `Based on these self-described personality keywords: ${kw}. ` +
    `Write a concise, warm, one-paragraph personality summary (2-3 sentences max, under 200 characters). ` +
    `Do not claim this is a scientific assessment. Write in third person. ` +
    `Return JSON {"summary": "..."}.`;
  const schema = {
    type: 'object',
    properties: {
      summary: {
        type: 'string',
        description: 'A concise, warm personality summary (2-3 sentences max, under 200 characters)'
      }
    },
    required: ['summary']
  };
  const res = await generateStructured({ prompt, schema, label: 'PersonalitySummary' });
  if (res && res.summary) return String(res.summary).trim();
  return null;
}

module.exports = {
  analyzeAudio, transcribeCaptions, sanitizeCaptions, translateCaptions, describePost, normalizeLanguage,
  CAPTION_LANGUAGES, classifyReplyText, normalizeStance, hasApiKeys, getApiKeys, MODELS_TO_TRY,
  generatePersonalitySummary
};


