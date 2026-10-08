double? calculateCwa(
  Iterable<({double score, double creditHours})> courses,
) {
  var totalCredits = 0.0;
  var weightedMarks = 0.0;
  for (final course in courses) {
    if (!course.score.isFinite ||
        !course.creditHours.isFinite ||
        course.score < 0 ||
        course.score > 100 ||
        course.creditHours <= 0) {
      continue;
    }
    totalCredits += course.creditHours;
    weightedMarks += course.score * course.creditHours;
  }
  return totalCredits == 0 ? null : weightedMarks / totalCredits;
}
