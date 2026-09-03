/// "Export BIDS dataset" — the whole tree, as one zip.
///
/// A zip rather than a directory picker because it is the one shape that works
/// identically on all five platforms: `exportFile` already knows how to hand a
/// single file to a desktop Save-As dialog or an iPad share sheet, and a
/// directory-writing path would need a separate implementation, separate
/// permissions and a separate failure mode on mobile for no gain — the recipient
/// unzips it into their dataset either way.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';

import '../app_info.dart';
import '../core/bids.dart';
import '../core/bids_dataset.dart';
import '../core/bids_sidecar.dart';
import 'share_util.dart';

/// Zip the dataset built from [entries] and deliver it.
///
/// [anchor] is the export button, for the iPad share popover.
Future<void> exportBidsDataset(
  BuildContext context, {
  required List<DatasetEntry> entries,
  GlobalKey? anchor,
}) async {
  if (entries.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nothing to export yet.')),
    );
    return;
  }
  // One subject means a name that says whose data it is; several means it does
  // not, and saying "bids-dataset" beats naming only the first of them.
  final subjects = {for (final e in entries) BidsName.label(e.name.subject)};
  final stem =
      subjects.length == 1 ? 'sub-${subjects.first}_bids' : 'bids-dataset';

  await exportFile(
    context,
    filename: '$stem.zip',
    anchor: anchor,
    failureLabel: 'BIDS export failed',
    build: () async {
      final files = buildBidsDataset(
        entries,
        appName: appName,
        appVersion: appVersion,
        repoUrl: repoUrl,
      );
      final archive = Archive();
      for (final file in files) {
        archive
            .addFile(ArchiveFile.bytes(file.path, utf8.encode(file.content)));
      }
      return (
        bytes: Uint8List.fromList(ZipEncoder().encode(archive)),
        warning: null,
      );
    },
  );
}

/// A [DatasetEntry] for one recorded file.
///
/// [kind] is `session_tsv` or `annotation_tsv`; the sidecar is generated from
/// the same contract that documents the columns in the docs, so the two cannot
/// disagree.
DatasetEntry datasetEntry({
  required BidsName name,
  required String tsv,
  required Map<String, dynamic> contract,
  required String kind,
  required String acqTime,
}) =>
    (
      name: name,
      tsv: tsv,
      sidecar: _encode(buildSidecar(contract, kind, appVersion: appVersion)),
      acqTime: acqTime.isEmpty ? 'n/a' : acqTime,
    );

String _encode(Map<String, dynamic> sidecar) =>
    '${const JsonEncoder.withIndent('  ').convert(sidecar)}\n';
