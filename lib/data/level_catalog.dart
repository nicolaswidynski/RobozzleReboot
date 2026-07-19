import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/level.dart';

/// Loads every scraped Robozzle level from the bundled JSON catalog
/// (assets/levels_catalog.json — see the scrape scripts used to build it).
Future<List<Level>> loadCatalogLevels() async {
  final jsonString = await rootBundle.loadString('assets/levels_catalog.json');
  final entries = json.decode(jsonString) as List;
  return entries.map((e) => Level.fromJson(e as Map<String, dynamic>)).toList();
}
