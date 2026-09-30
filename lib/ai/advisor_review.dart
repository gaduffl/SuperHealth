import 'dart:convert';

import 'clinical_digest.dart';

/// One judged item: what it is, as the reader knows it, and why it matters.
class ReviewVerdict {
  const ReviewVerdict({required this.what, required this.why});

  final String what;
  final String why;

  Map<String, Object?> toJson() => {'what': what, 'why': why};
}

/// The advisor's explicit judgement of every current exposure and finding.
///
/// This replaces a receipt that only proved the model could copy a hash the
/// prompt handed it. A verdict per item proves something: the model was made
/// to think about biotin even when the question was about TSH and nothing in
/// it pointed at biotin. Code checks that every checklist item has one;
/// anything left out is named on screen as not assessed rather than implied
/// to be irrelevant.
class AdvisorReview {
  const AdvisorReview({
    required this.relevant,
    required this.uncertain,
    required this.notRelevant,
    required this.notAssessed,
  });

  final List<ReviewVerdict> relevant;
  final List<ReviewVerdict> uncertain;
  final List<String> notRelevant;

  /// Checklist items the model never judged.
  final List<String> notAssessed;

  bool get complete => notAssessed.isEmpty;

  int get assessedCount =>
      relevant.length + uncertain.length + notRelevant.length;

  bool get isEmpty => assessedCount == 0 && notAssessed.isEmpty;

  Map<String, Object?> toJson() => {
    'v': 1,
    'relevant': [for (final item in relevant) item.toJson()],
    'uncertain': [for (final item in uncertain) item.toJson()],
    'not_relevant': notRelevant,
    'not_assessed': notAssessed,
  };

  static AdvisorReview? fromJson(Object? json) {
    if (json is! Map) return null;
    List<ReviewVerdict> verdicts(Object? value) => [
      if (value is List)
        for (final item in value)
          if (item is Map && item['what'] != null)
            ReviewVerdict(
              what: item['what'].toString(),
              why: item['why']?.toString() ?? '',
            ),
    ];
    List<String> names(Object? value) => [
      if (value is List)
        for (final item in value)
          if (item != null) item.toString(),
    ];
    return AdvisorReview(
      relevant: verdicts(json['relevant']),
      uncertain: verdicts(json['uncertain']),
      notRelevant: names(json['not_relevant']),
      notAssessed: names(json['not_assessed']),
    );
  }
}

/// What came back, split into the answer and its review.
class ParsedAdvisorReply {
  const ParsedAdvisorReply({
    required this.answer,
    required this.review,
    required this.missing,
    required this.blockFound,
  });

  /// The answer with every review block removed.
  final String answer;
  final AdvisorReview review;

  /// Checklist items without a verdict, for a follow-up request.
  final List<ReviewItem> missing;
  final bool blockFound;
}

final _block = RegExp(
  r'<exposure_review>\s*([\s\S]*?)\s*</exposure_review>',
  caseSensitive: false,
);

/// Reads the review block at the start of a reply against [checklist].
///
/// Tolerant of the shapes models actually produce — a fenced code block
/// inside the tags, verdicts given as objects in `not_relevant` — because a
/// review lost to a formatting quirk would be reported as "not assessed" for
/// items the model did assess. Ids that are not on the checklist are ignored,
/// never invented into verdicts.
ParsedAdvisorReply parseAdvisorReply(String text, List<ReviewItem> checklist) {
  final matches = _block.allMatches(text).toList();
  final answer = text.replaceAll(_block, '').trim();
  final byId = {for (final item in checklist) item.id: item};
  final judged = <String>{};
  final relevant = <ReviewVerdict>[];
  final uncertain = <ReviewVerdict>[];
  final notRelevant = <String>[];

  Object? decoded;
  if (matches.isNotEmpty) {
    var body = matches.first.group(1)!.trim();
    final fence = RegExp(r'^```[a-zA-Z]*\s*([\s\S]*?)\s*```$').firstMatch(body);
    if (fence != null) body = fence.group(1)!;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      decoded = null;
    }
  }

  void addVerdicts(Object? value, List<ReviewVerdict> into) {
    if (value is! List) return;
    for (final entry in value) {
      final id = entry is Map ? entry['id']?.toString() : entry?.toString();
      final item = byId[id];
      if (item == null || !judged.add(item.id)) continue;
      final why = entry is Map ? entry['why']?.toString().trim() ?? '' : '';
      into.add(ReviewVerdict(what: item.label, why: why));
    }
  }

  if (decoded is Map) {
    addVerdicts(decoded['relevant'], relevant);
    addVerdicts(decoded['uncertain'], uncertain);
    final plain = decoded['not_relevant'];
    if (plain is List) {
      for (final entry in plain) {
        final id = entry is Map ? entry['id']?.toString() : entry?.toString();
        final item = byId[id];
        if (item == null || !judged.add(item.id)) continue;
        notRelevant.add(item.label);
      }
    }
  }
  final missing = [
    for (final item in checklist)
      if (!judged.contains(item.id)) item,
  ];
  return ParsedAdvisorReply(
    answer: answer,
    review: AdvisorReview(
      relevant: relevant,
      uncertain: uncertain,
      notRelevant: notRelevant,
      notAssessed: [for (final item in missing) item.label],
    ),
    missing: missing,
    blockFound: decoded is Map,
  );
}

/// Where a stored answer's review begins.
///
/// An HTML comment, so any markdown view that is not review-aware shows the
/// answer alone; the advisor screen splits here and renders the review in the
/// reader's language. The JSON carries names and reasons, never record ids.
const reviewSentinel = '<!-- superhealth-review ';

String withReviewSection(String answer, AdvisorReview review) {
  if (review.isEmpty) return answer;
  // "-->" inside a reason would end the comment early in an HTML renderer.
  final json = jsonEncode(review.toJson()).replaceAll('-->', r'--\u003e');
  return '$answer\n\n$reviewSentinel$json -->';
}

/// The answer and, when present, the review stored with it.
({String answer, AdvisorReview? review}) splitReviewSection(String content) {
  final start = content.indexOf(reviewSentinel);
  if (start < 0) return (answer: content, review: null);
  final answer = content.substring(0, start).trimRight();
  final rest = content.substring(start + reviewSentinel.length);
  final end = rest.lastIndexOf('-->');
  AdvisorReview? review;
  try {
    review = AdvisorReview.fromJson(
      jsonDecode(end < 0 ? rest : rest.substring(0, end)),
    );
  } on FormatException {
    review = null;
  }
  return (answer: answer, review: review);
}

/// The answer alone, for replaying history: a past review is bookkeeping for
/// the reader, and re-sending it would teach the model to copy old verdicts.
String withoutReviewSection(String content) =>
    splitReviewSection(content).answer;
