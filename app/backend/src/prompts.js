// The question of the day. One prompt per calendar day, chosen from this list by the date alone, so every person sees the same one and
// no table is needed. People answer it with a video opinion (POST /api/posts with promptDay), which gives a new person something to say
// and gives everyone a common thread to read. Prompts are plain questions with two honest sides; add more, keep them neutral.
// `topic` is a topic id from topics.js.

const PROMPTS = [
  { topic: 'education', text: 'Should attendance be compulsory in colleges?' },
  { topic: 'education', text: 'Is a degree still the best route to a good career?' },
  { topic: 'education', text: 'Should every student have to learn a trade or skill before graduating?' },
  { topic: 'jobs', text: 'Is a four-day work week a good idea for India?' },
  { topic: 'jobs', text: 'Should internships always be paid?' },
  { topic: 'jobs', text: 'Is a government job still better than a private one?' },
  { topic: 'politics', text: 'Should the voting age be lowered to 16?' },
  { topic: 'politics', text: 'Should there be a limit on how long one person can hold office?' },
  { topic: 'politics', text: 'Should elections for the state and the centre happen together?' },
  { topic: 'economy', text: 'Should the rich be taxed more to pay for public services?' },
  { topic: 'economy', text: 'Is working from home better for the economy than working in an office?' },
  { topic: 'economy', text: 'Should basic goods have a price cap?' },
  { topic: 'tech', text: 'Should social media be restricted for under-16s?' },
  { topic: 'tech', text: 'Will AI create more jobs than it takes away?' },
  { topic: 'tech', text: 'Should apps be allowed to track what you watch in order to show you ads?' },
  { topic: 'environment', text: 'Should plastic bags be banned completely?' },
  { topic: 'environment', text: 'Should cities charge cars to drive into the centre?' },
  { topic: 'environment', text: 'Is nuclear power the answer to clean electricity?' },
  { topic: 'health', text: 'Should junk food adverts be banned?' },
  { topic: 'health', text: 'Should mental health days count as sick days?' },
  { topic: 'health', text: 'Should private hospitals have to treat emergencies for free?' },
  { topic: 'law', text: 'Should the death penalty exist?' },
  { topic: 'law', text: 'Should police wear body cameras all the time?' },
  { topic: 'law', text: 'Should people be prosecuted for what they post online?' },
  { topic: 'society', text: 'Is it right to choose your own partner without family approval?' },
  { topic: 'society', text: 'Should caste be removed from every official form?' },
  { topic: 'society', text: 'Should schools teach in the mother tongue until class eight?' },
  { topic: 'sports', text: 'Should India put more money into Olympic sports than into cricket?' },
  { topic: 'sports', text: 'Should sports stars be paid more than doctors?' },
  { topic: 'sports', text: 'Should every school have to give daily sports time?' },
  { topic: 'entertainment', text: 'Should films be censored at all?' },
  { topic: 'entertainment', text: 'Is streaming better than cinema?' },
  { topic: 'entertainment', text: 'Should creators be paid by the platform for every view?' },
  { topic: 'ethics', text: 'Is it ever right to break a law you believe is unjust?' },
  { topic: 'ethics', text: 'Should religion have any place in public schools?' },
  { topic: 'ethics', text: 'Is it wrong to eat meat?' },
  { topic: 'startups', text: 'Should a student drop out to build a startup?' },
  { topic: 'startups', text: 'Do startups in India need more government help or less?' },
  { topic: 'startups', text: 'Is it better to start a company or build a career inside one?' },
  { topic: 'world', text: 'Should India stay out of other countries\' wars?' },
  { topic: 'world', text: 'Should rich countries pay more for climate damage?' },
  { topic: 'world', text: 'Is globalisation good for ordinary people?' },
  { topic: 'farming', text: 'Should farm loans be waived?' },
  { topic: 'farming', text: 'Should farmers be free to sell anywhere in the country?' },
  { topic: 'farming', text: 'Is organic farming realistic for a country this size?' },
  { topic: 'campus', text: 'Should colleges ban phones in the classroom?' },
  { topic: 'campus', text: 'Should hostels have no curfew?' },
  { topic: 'campus', text: 'Should students grade their professors in public?' }
];

const DAY_MS = 86400000;
const IST_MINUTES = 330; // the pilot is in India; a new question starts at 5:30 in the morning, not at midnight in London

/** The calendar day for a time in ms, as YYYY-MM-DD, in the prompt time zone (PROMPT_UTC_OFFSET_MIN, default India). */
function dayKey(ms, offsetMin = IST_MINUTES) {
  return new Date(ms + offsetMin * 60000).toISOString().slice(0, 10);
}

/** The question for a day (YYYY-MM-DD), or null when the string is not a day. */
function promptFor(day) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(day))) return null;
  const t = Date.parse(`${day}T00:00:00Z`);
  if (Number.isNaN(t)) return null;
  const n = Math.floor(t / DAY_MS);
  const p = PROMPTS[((n % PROMPTS.length) + PROMPTS.length) % PROMPTS.length];
  return { day, text: p.text, topic: p.topic };
}

/** Today's day and yesterday's: the two questions people may still answer. */
function openDays(ms, offsetMin = IST_MINUTES) {
  return [dayKey(ms, offsetMin), dayKey(ms - DAY_MS, offsetMin)];
}

module.exports = { PROMPTS, dayKey, promptFor, openDays };
