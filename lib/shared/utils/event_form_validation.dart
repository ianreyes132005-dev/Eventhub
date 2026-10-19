import 'package:flutter/material.dart';

/// Fields of the organizer's create / edit event form (web dialog and mobile
/// screen), in the order they appear on screen. There's no capacity field —
/// capacity is the number of active students (StudentCountService).
enum EventFormField { title, otherType, startDate, endDate, startTime, endTime, location }

/// Every problem with the form at once, keyed by field, in screen order.
/// Empty when the form can be saved. Mirrors the database schedule rules
/// (assert_valid_schedule): the start can't be in the past and the end must
/// be after the start.
Map<EventFormField, String> validateEventForm({
  required String     title,
  required bool       needsOtherType,
  required String     otherType,
  required DateTime?  startDate,
  required DateTime?  endDate,
  required TimeOfDay? startTime,
  required TimeOfDay? endTime,
  required String     location,
  DateTime?           now,
}) {
  final e = <EventFormField, String>{};

  if (title.trim().isEmpty) e[EventFormField.title] = 'Give the event a name.';
  if (needsOtherType && otherType.trim().isEmpty) {
    e[EventFormField.otherType] = 'Type what kind of event this is.';
  }

  if (startDate == null) e[EventFormField.startDate] = 'Pick a start date.';
  if (endDate == null) {
    e[EventFormField.endDate] = 'Pick an end date.';
  } else if (startDate != null && DateUtils.dateOnly(endDate).isBefore(DateUtils.dateOnly(startDate))) {
    e[EventFormField.endDate] = 'The end date can’t be before the start date.';
  }
  if (startTime == null) e[EventFormField.startTime] = 'Pick a start time.';
  if (endTime == null) e[EventFormField.endTime] = 'Pick an end time.';

  if (startDate != null && endDate != null && startTime != null && endTime != null &&
      !e.containsKey(EventFormField.endDate)) {
    final start = DateTime(startDate.year, startDate.month, startDate.day,
        startTime.hour, startTime.minute);
    final end = DateTime(endDate.year, endDate.month, endDate.day,
        endTime.hour, endTime.minute);
    if (!start.isAfter(now ?? DateTime.now())) {
      e[EventFormField.startTime] = 'This start time has already passed.';
    }
    if (!end.isAfter(start)) {
      e[EventFormField.endTime] = 'The end must be after the start.';
    }
  }

  if (location.trim().isEmpty) e[EventFormField.location] = 'Enter where the event will be held.';

  return Map.fromEntries(e.entries.toList()
    ..sort((a, b) => a.key.index.compareTo(b.key.index)));
}
