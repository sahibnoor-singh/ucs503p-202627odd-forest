/**
 * recommendation.js (ported from Website/backend/services/recommendationService.js; context.now makes freshness testable)
 * 
 * Implements the Personal Interest Prediction Score (PIPS) and User Interest Profile learning
 * for the FORREST Smart Feed & Debate Navigation.
 * 
 * Formula:
 * PIPS = 100 * (
 *   0.30 * predicted_watch_interest +
 *   0.20 * topic_affinity +
 *   0.10 * creator_affinity +
 *   0.15 * debate_relevance +
 *   0.10 * novelty_and_curiosity +
 *   0.10 * historical_engagement +
 *   0.05 * freshness
 * ) - repetition_penalty
 * 
 * Normalization: Each feature is in [0, 1]. Final score clamped to [0, 100].
 * 
 * Core Principles:
 * 1. Viewing != Agreeing: Watching a FOR or AGAINST video does not alter political bias / stance preference.
 * 2. Topic & Creator Diversity: Novelty feature and repetition penalties prevent echo chambers and fatigue.
 * 3. Extensible for Future ML: Weights and feature extractors are decoupled and configurable.
 */

// Configurable weights for PIPS scoring
const DEFAULT_WEIGHTS = {
  predictedWatchInterest: 0.30,
  topicAffinity: 0.20,
  creatorAffinity: 0.10,
  debateRelevance: 0.15,
  noveltyCuriosity: 0.10,
  historicalEngagement: 0.10,
  freshness: 0.05
};

// Configurable penalties
const DEFAULT_PENALTIES = {
  repetitionPenaltyPerRecentView: 15.0, // Subtracted if viewed recently
  repetitionPenaltyPerSkip: 25.0,       // Higher penalty if recently skipped
  maxRepetitionPenalty: 50.0
};

/**
 * Extracts normalized topic tokens from video title, caption, and transcript.
 */
function extractTopics(video) {
  if (!video) return [];
  const tokens = new Set();

  function addWords(text) {
    if (!text || typeof text !== 'string') return;
    const cleaned = text.toLowerCase().replace(/[^a-z0-9\s]/g, ' ');
    cleaned.split(/\s+/).forEach(w => {
      if (w.length >= 3 && !['the', 'and', 'for', 'are', 'with', 'that', 'this', 'from', 'have', 'was'].includes(w)) {
        tokens.add(w);
      }
    });
  }

  addWords(video.title);
  addWords(video.caption);

  if (video.transcript) {
    let t = video.transcript;
    if (typeof t === 'string') {
      try { t = JSON.parse(t); } catch (_) { addWords(t); }
    }
    if (typeof t === 'object' && t !== null) {
      if (t.transcript) addWords(t.transcript);
      if (t.overallSummary) addWords(t.overallSummary);
      if (Array.isArray(t.claims)) {
        t.claims.forEach(c => {
          if (typeof c === 'string') addWords(c);
          else if (c && c.claim) addWords(c.claim);
        });
      }
      if (Array.isArray(t.topics)) {
        t.topics.forEach(tp => addWords(tp));
      }
    }
  }

  return Array.from(tokens);
}

/**
 * Normalizes a number to [0, 1] using min-max bounds or clamping.
 */
function clamp01(val) {
  if (isNaN(val) || val === null || val === undefined) return 0;
  return Math.max(0, Math.min(1, Number(val)));
}

/**
 * Computes individual normalized features (each [0, 1]) for a video relative to a user profile and context.
 */
function extractFeatures(video, userProfile = null, context = {}) {
  const profile = userProfile || {
    topics: {},
    creators: {},
    recentViews: [],
    interactionCounts: { completions: 0, skips: 0, rewatches: 0, saves: 0, shares: 0, likes: 0 }
  };

  const videoTopics = extractTopics(video);
  const creator = video.userName || video.userId || 'unknown';

  // 1. Predicted Watch Interest [0, 1]
  // Based on video completion rate from all viewers, with baseline 0.5
  let predictedWatch = 0.5;
  if (video.totalViews && video.totalViews > 0) {
    const completionRate = (video.completedViews || 0) / video.totalViews;
    predictedWatch = 0.3 + (completionRate * 0.7);
  } else if (video.credibility) {
    // Higher credibility slightly boosts initial expected watch interest
    predictedWatch = 0.4 + (clamp01(video.credibility / 100) * 0.3);
  }
  predictedWatch = clamp01(predictedWatch);

  // 2. Topic Affinity [0, 1]
  let topicAffinity = 0.5; // neutral baseline for new topics
  if (profile.topics && Object.keys(profile.topics).length > 0 && videoTopics.length > 0) {
    let matchedSum = 0;
    let matchCount = 0;
    videoTopics.forEach(t => {
      if (profile.topics[t] !== undefined) {
        matchedSum += profile.topics[t];
        matchCount++;
      }
    });
    if (matchCount > 0) {
      // Average affinity of matched topics
      topicAffinity = clamp01(matchedSum / matchCount);
    }
  }

  // 3. Creator Affinity [0, 1]
  let creatorAffinity = 0.5;
  if (profile.creators && profile.creators[creator] !== undefined) {
    creatorAffinity = clamp01(profile.creators[creator]);
  }

  // 4. Relevance to Current Debate [0, 1]
  let debateRelevance = 1.0;
  if (context.parentVideo) {
    // Reply ranking mode: semantic / topic overlap between child and parent
    const parentTopics = extractTopics(context.parentVideo);
    if (parentTopics.length > 0 && videoTopics.length > 0) {
      const parentSet = new Set(parentTopics);
      const overlap = videoTopics.filter(t => parentSet.has(t)).length;
      debateRelevance = clamp01(0.3 + (overlap / Math.min(parentTopics.length, 5)) * 0.7);
    } else {
      debateRelevance = 0.7; // default moderate relevance if parent has few keywords
    }
  } else {
    // Main feed mode: independent videos are self-contained debates
    debateRelevance = 0.85;
  }

  // 5. Novelty and Curiosity [0, 1]
  // Rewards topics/creators the user has NOT seen recently, actively breaking echo chambers
  let novelty = 0.8;
  if (profile.recentViews && profile.recentViews.length > 0) {
    const recentCreatorCount = profile.recentViews.filter(v => v.creator === creator).length;
    // Penalty for over-represented creators in recent window
    novelty = clamp01(1.0 - (recentCreatorCount * 0.25));
  }

  // 6. Meaningful Historical Engagement [0, 1]
  // Based on video like ratio, credibility, and debate reply activity
  let historicalEngagement = 0.5;
  const credibilityNorm = clamp01((video.credibility || 50) / 100);
  const likeRatio = (video.likeCount || 0) > 0 ? Math.min(1.0, (video.likeCount || 0) / 20) : 0.3;
  const replyActivity = (video.replyCount || 0) > 0 ? Math.min(1.0, (video.replyCount || 0) / 5) : 0.2;
  historicalEngagement = clamp01((credibilityNorm * 0.4) + (likeRatio * 0.3) + (replyActivity * 0.3));

  // 7. Freshness [0, 1]
  let freshness = 0.8;
  if (video.createdAt) {
    const ageHours = Math.max(0, ((context.now == null ? Date.now() : context.now) - new Date(video.createdAt).getTime()) / (1000 * 60 * 60));
    // Half-life of 48 hours for freshness
    freshness = clamp01(Math.exp(-ageHours / 48));
  }

  // 8. Repetition Penalty [0, 50]
  let repetitionPenalty = 0;
  if (profile.recentViews && Array.isArray(profile.recentViews)) {
    const viewsOfThisVideo = profile.recentViews.filter(v => v.videoId === video.id);
    if (viewsOfThisVideo.length > 0) {
      viewsOfThisVideo.forEach(view => {
        if (view.skipped) {
          repetitionPenalty += DEFAULT_PENALTIES.repetitionPenaltyPerSkip;
        } else {
          repetitionPenalty += DEFAULT_PENALTIES.repetitionPenaltyPerRecentView;
        }
      });
    }
  }
  repetitionPenalty = Math.min(DEFAULT_PENALTIES.maxRepetitionPenalty, repetitionPenalty);

  return {
    predictedWatchInterest: clamp01(predictedWatch),
    topicAffinity: clamp01(topicAffinity),
    creatorAffinity: clamp01(creatorAffinity),
    debateRelevance: clamp01(debateRelevance),
    noveltyCuriosity: clamp01(novelty),
    historicalEngagement: clamp01(historicalEngagement),
    freshness: clamp01(freshness),
    repetitionPenalty: repetitionPenalty
  };
}

/**
 * Calculates the final Personal Interest Prediction Score (PIPS) for a video.
 * Returns score clamped to [0, 100] and detailed breakdown.
 */
function computePIPS(video, userProfile = null, context = {}, customWeights = null) {
  const weights = { ...DEFAULT_WEIGHTS, ...(customWeights || {}) };
  const features = extractFeatures(video, userProfile, context);

  const weightedSum =
    (weights.predictedWatchInterest * features.predictedWatchInterest) +
    (weights.topicAffinity * features.topicAffinity) +
    (weights.creatorAffinity * features.creatorAffinity) +
    (weights.debateRelevance * features.debateRelevance) +
    (weights.noveltyCuriosity * features.noveltyCuriosity) +
    (weights.historicalEngagement * features.historicalEngagement) +
    (weights.freshness * features.freshness);

  const rawScore = (100 * weightedSum) - features.repetitionPenalty;
  const clampedScore = Math.max(0, Math.min(100, Math.round(rawScore * 100) / 100));

  return {
    pips: clampedScore,
    features,
    weights
  };
}

/**
 * Ranks a list of videos using PIPS.
 */
function rankVideos(videos, userProfile = null, context = {}) {
  if (!videos || !Array.isArray(videos)) return [];

  const scored = videos.map(video => {
    const scoring = computePIPS(video, userProfile, context);
    return {
      ...video,
      pipsScore: scoring.pips,
      pipsDetails: scoring
    };
  });

  // Sort descending by PIPS score
  scored.sort((a, b) => b.pipsScore - a.pipsScore);
  return scored;
}

/**
 * Learns and updates user interest profile based on an interaction event.
 * NOTE: Watching a viewpoint does NOT equate to agreement. We strictly update topic and creator affinities
 * and engagement statistics, without mutating political stance leanings.
 */
function updateProfileWithInteraction(profile, video, interaction) {
  const current = profile || {
    userId: interaction.userId,
    topics: {},
    creators: {},
    recentViews: [],
    watchTimeTotal: 0,
    interactionCounts: { completions: 0, skips: 0, rewatches: 0, saves: 0, shares: 0, likes: 0 }
  };

  const topics = extractTopics(video);
  const creator = video.userName || video.userId || 'unknown';
  const watchMs = Number(interaction.watchDurationMs) || 0;
  const completed = Boolean(interaction.completed);
  const skipped = Boolean(interaction.skipped);
  const rewatched = Boolean(interaction.rewatched);
  const saved = Boolean(interaction.saved);
  const shared = Boolean(interaction.shared);
  const liked = Boolean(interaction.liked); // an explicit like: a clear sign of interest in the topics and the creator

  current.watchTimeTotal = (current.watchTimeTotal || 0) + watchMs;

  // Track raw interaction counts
  if (completed) current.interactionCounts.completions++;
  if (skipped) current.interactionCounts.skips++;
  if (rewatched) current.interactionCounts.rewatches++;
  if (saved) current.interactionCounts.saves++;
  if (shared) current.interactionCounts.shares++;
  if (liked) current.interactionCounts.likes++;

  // Calculate learning delta for interest (bounded between -0.2 and +0.3)
  let delta = 0.05; // baseline interest for watching
  if (completed) delta += 0.15;
  if (rewatched) delta += 0.20;
  if (saved) delta += 0.25;
  if (shared) delta += 0.25;
  if (liked) delta += 0.2;
  if (skipped) delta = -0.15;

  // Update Topic Affinities with exponential smoothing (learning rate 0.2)
  topics.forEach(t => {
    const existing = current.topics[t] !== undefined ? current.topics[t] : 0.5;
    const updated = existing + (0.2 * delta);
    current.topics[t] = Math.max(0.0, Math.min(1.0, Math.round(updated * 1000) / 1000));
  });

  // Update Creator Affinity (learning rate 0.15)
  const existingCreator = current.creators[creator] !== undefined ? current.creators[creator] : 0.5;
  const updatedCreator = existingCreator + (0.15 * delta);
  current.creators[creator] = Math.max(0.0, Math.min(1.0, Math.round(updatedCreator * 1000) / 1000));

  // Maintain recent views queue (max 50 items for repetition and novelty tracking). A like is not another view.
  current.recentViews = current.recentViews || [];
  if (!interaction.noView) current.recentViews.unshift({
    videoId: video.id,
    creator: creator,
    timestamp: interaction.at || new Date().toISOString(),
    skipped: skipped,
    completed: completed
  });
  if (current.recentViews.length > 50) {
    current.recentViews = current.recentViews.slice(0, 50);
  }

  return current;
}

/** Keeps a profile from growing without bound: drops the topics closest to the neutral 0.5. */
function pruneProfile(profile, maxTopics = 300, maxCreators = 200) {
  const prune = (map, max) => {
    const keys = Object.keys(map);
    if (keys.length <= max) return;
    keys.sort((a, b) => Math.abs(map[b] - 0.5) - Math.abs(map[a] - 0.5));
    keys.slice(max).forEach((k) => delete map[k]);
  };
  prune(profile.topics, maxTopics);
  prune(profile.creators, maxCreators);
  return profile;
}

module.exports = {
  pruneProfile,
  DEFAULT_WEIGHTS,
  DEFAULT_PENALTIES,
  extractTopics,
  extractFeatures,
  computePIPS,
  rankVideos,
  updateProfileWithInteraction
};
