// The topics a new person can pick in onboarding, and the words each one stands for. The words are what the taste profile
// (recommendation.js, extractTopics) actually matches on: lower-case tokens of three or more letters from titles, captions and
// transcripts. Keep each list to words people really say, not to the label.

const TOPICS = [
  { id: 'politics', label: 'Politics', words: ['politics', 'political', 'election', 'vote', 'government', 'parliament', 'party', 'minister', 'policy', 'democracy'] },
  { id: 'economy', label: 'Economy', words: ['economy', 'economic', 'inflation', 'tax', 'budget', 'market', 'prices', 'gdp', 'trade', 'rupee'] },
  { id: 'jobs', label: 'Jobs and careers', words: ['jobs', 'job', 'career', 'unemployment', 'salary', 'hiring', 'internship', 'placement', 'skills', 'workers'] },
  { id: 'education', label: 'Education', words: ['education', 'school', 'college', 'university', 'exam', 'exams', 'students', 'teachers', 'degree', 'syllabus'] },
  { id: 'campus', label: 'Campus life', words: ['campus', 'hostel', 'fest', 'society', 'canteen', 'professor', 'attendance', 'semester', 'freshers', 'mess'] },
  { id: 'tech', label: 'Technology and AI', words: ['technology', 'tech', 'internet', 'software', 'robots', 'automation', 'privacy', 'algorithm', 'smartphone', 'data'] },
  { id: 'environment', label: 'Environment', words: ['environment', 'climate', 'pollution', 'energy', 'water', 'forest', 'forests', 'emissions', 'waste', 'solar'] },
  { id: 'health', label: 'Health', words: ['health', 'hospital', 'doctor', 'medicine', 'mental', 'fitness', 'diet', 'disease', 'vaccine', 'wellbeing'] },
  { id: 'law', label: 'Law and rights', words: ['law', 'laws', 'court', 'rights', 'justice', 'police', 'constitution', 'freedom', 'crime', 'legal'] },
  { id: 'society', label: 'Society and culture', words: ['society', 'culture', 'caste', 'gender', 'family', 'tradition', 'marriage', 'language', 'youth', 'community'] },
  { id: 'sports', label: 'Sports', words: ['sports', 'cricket', 'football', 'match', 'team', 'olympics', 'players', 'coach', 'league', 'tournament'] },
  { id: 'entertainment', label: 'Entertainment', words: ['movie', 'movies', 'film', 'music', 'actor', 'cinema', 'series', 'celebrity', 'streaming', 'songs'] },
  { id: 'ethics', label: 'Ethics and religion', words: ['ethics', 'moral', 'religion', 'faith', 'belief', 'values', 'secular', 'temple', 'philosophy', 'conscience'] },
  { id: 'startups', label: 'Startups and business', words: ['startup', 'startups', 'business', 'founder', 'funding', 'entrepreneur', 'company', 'investors', 'product', 'profit'] },
  { id: 'world', label: 'Foreign affairs', words: ['foreign', 'china', 'pakistan', 'america', 'war', 'border', 'diplomacy', 'global', 'sanctions', 'treaty'] },
  { id: 'farming', label: 'Farming and villages', words: ['farmers', 'farming', 'agriculture', 'crops', 'village', 'rural', 'msp', 'harvest', 'irrigation', 'subsidy'] }
];

const MIN_PICK = 3; // what the app asks for; the server accepts fewer (skipping is allowed)
const MAX_PICK = 8;
const SEED_AFFINITY = 0.7; // a little above the neutral 0.5, so watching can move it either way

const BY_ID = new Map(TOPICS.map((t) => [t.id, t]));

/** The list the app shows. */
const publicTopics = () => TOPICS.map(({ id, label }) => ({ id, label }));

/** Puts the chosen topics' words into a taste profile without lowering anything the person already earned. */
function seedProfile(profile, ids) {
  for (const id of ids) {
    for (const word of BY_ID.get(id).words) {
      profile.topics[word] = Math.max(profile.topics[word] === undefined ? 0 : profile.topics[word], SEED_AFFINITY);
    }
  }
  profile.interests = [...ids];
  return profile;
}

module.exports = { TOPICS, MIN_PICK, MAX_PICK, SEED_AFFINITY, publicTopics, seedProfile, isTopicId: (id) => BY_ID.has(id) };
