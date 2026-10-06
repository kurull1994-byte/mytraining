import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:xml/xml.dart';

class ProgramSourceReader {
  static String fromText(String text) => text.trim();

  static String fromSpreadsheet(Uint8List bytes) {
    final decoder = SpreadsheetDecoder.decodeBytes(bytes);
    final out=<String>[];
    for(final entry in decoder.tables.entries){
      out.add('Лист: '+entry.key);
      for(final row in entry.value.rows){
        final cells=row.map((e)=>e?.toString().trim()??'').where((e)=>e.isNotEmpty).toList();
        if(cells.isNotEmpty) out.add(cells.join(' | '));
      }
    }
    return out.join('\n');
  }

  static String fromDocx(Uint8List bytes) {
    final archive=ZipDecoder().decodeBytes(bytes);
    final file=archive.findFile('word/document.xml');
    if(file==null) return '';
    final data=file.content;
    final xml=XmlDocument.parse(utf8.decode(data is Uint8List ? data : Uint8List.fromList(List<int>.from(data))));
    return xml.descendants.whereType<XmlElement>().where((e)=>e.name.local=='t').map((e)=>e.innerText).join(' ');
  }
}