// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library tuneup.dep_check_command;

import 'dart:async';
import 'dart:io';

import 'package:yaml/yaml.dart';

import 'common.dart';

class DepCheckCommand extends Command {

  DepCheckCommand() : super('depcheck',
      'Check for unused dependencies listed in your pubspec.yaml');

  List<String> getDependencyNames(YamlMap pubspec) {
    Map<String, dynamic> dependencies = pubspec['dependencies'];
    return dependencies != null ? dependencies.keys.toList() : [];
  }

  List<String> getDevDependencyNames(YamlMap pubspec) {
    Map<String, dynamic> dependencies = pubspec['dev_dependencies'];
    return dependencies != null ? dependencies.keys.toList() : [];
  }

  List<String> getTransformerNames(YamlMap pubspec) {
    YamlList transformers = pubspec['transformers'];
    var entries = transformers?.map((entry) {
      if (entry is String) {
        return entry;
      } else if (entry is YamlMap) {
        return entry.keys.first;
      }
    });
    return entries ?? [];
  }

  Future execute(Project project, [args]) {
    bool verbose = args == null ? false : args['verbose'];

    Stopwatch stopwatch = new Stopwatch()..start();

    var pubspec = project.pubspec;
    var unusedDependencies = getDependencyNames(pubspec);
    var unusedDevDependencies = getDevDependencyNames(pubspec);
    for (var transformer in getTransformerNames(pubspec)) {
      var findTransformerPackage = new RegExp(r'\s*([^/]+)(\/|\:|$)');
      var match = findTransformerPackage.firstMatch(transformer);
      if (match?.group(1) != null) {
        if (unusedDependencies.remove(match.group(1))) {
          if (verbose) {
            project.print('package used as transformer: ${match.group(1)}');
          }
        }
      }
    }

    var projectFiles = project.getSourceFiles(extensions: const['dart', 'htm', 'html']);
    for (File file in projectFiles) {
      final separator = Platform.pathSeparator;
      final isDevFile = file.path.contains(new RegExp('${project.dir.path}${separator}(${Project.PUB_DEV_FOLDERS.join('|')})${separator}'));

      var extension = getFileExtension(file.path);
      List<String> matches;
      if (extension == 'dart') {
        var findImported = new RegExp('import\\s+(\'|")package\:([^/]+)\/');
        var allMatches = findImported.allMatches(file.readAsStringSync());
        matches = allMatches.map((match) => match.group(2));
      } else {
        var findImported = new RegExp('(src|href)=(\'|")\/?packages\/([^/]+)');
        var allMatches = findImported.allMatches(file.readAsStringSync());
        matches = allMatches.map((match) => match.group(3));
      }

      for (var match in matches) {
        bool removed = isDevFile ? unusedDevDependencies.remove(match) : unusedDependencies.remove(match);
        if (removed && verbose) {
          project.print('$match package imported in $extension file: ${file.path}');
        }
      }
    }

    if (unusedDependencies.isEmpty) {
      project.print('No unused dependencies, nice!');
    } else {
      project.print('The following may be unused dependencies:\n${unusedDependencies.join(', ')}');
    }

    if (unusedDevDependencies.isEmpty) {
      project.print('No unused dev_dependencies, nice!');
    } else {
      project.print('The following may be unused dev_dependencies:\n${unusedDevDependencies.join(', ')}');
    }


    stopwatch.stop();

    var seconds = (stopwatch.elapsedMilliseconds ~/ 100) * 100 / 1000;
    project.print('Finished depcheck in ${seconds}s.');

    return new Future.value();
  }
}
