import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class AiGateway {
  static const _keyName='openai_api_key';
  static const _baseName='ai_base_url';
  static const _modelName='ai_model';
  final FlutterSecureStorage storage;
  AiGateway({FlutterSecureStorage? storage}) : storage=storage ?? const FlutterSecureStorage();

  Future<String?> apiKey() => storage.read(key:_keyName);
  Future<String> baseUrl() async => (await storage.read(key:_baseName))?.trim().replaceFirst(RegExp(r'/+$'), '') ?? 'https://api.openai.com/v1';
  Future<String> model() async => (await storage.read(key:_modelName))?.trim().isNotEmpty == true ? (await storage.read(key:_modelName))!.trim() : 'gpt-6-luna';
  Future<void> saveSettings({required String apiKey,required String baseUrl,required String model}) async {
    await storage.write(key:_keyName,value:apiKey.trim());
    await storage.write(key:_baseName,value:baseUrl.trim().replaceFirst(RegExp(r'/+$'), ''));
    await storage.write(key:_modelName,value:model.trim().isEmpty ? 'gpt-6-luna' : model.trim());
  }
  Future<void> clearKey() => storage.delete(key:_keyName);

  static Map<String,dynamic> schema = {
    'type':'object',
    'additionalProperties':false,
    'properties':{
      'name':{'type':'string'},
      'weeks':{'type':'array','items':{
        'type':'object','additionalProperties':false,
        'properties':{
          'number':{'type':'integer'},
          'days':{'type':'array','items':{
            'type':'object','additionalProperties':false,
            'properties':{
              'name':{'type':'string'},
              'exercises':{'type':'array','items':{
                'type':'object','additionalProperties':false,
                'properties':{
                  'name':{'type':'string'},
                  'sets':{'type':'array','items':{
                    'type':'object','additionalProperties':false,
                    'properties':{
                      'weight':{'anyOf':[{'type':'number'},{'type':'null'}]},
                      'reps':{'anyOf':[{'type':'integer'},{'type':'null'}]},
                      'percentage':{'anyOf':[{'type':'number'},{'type':'null'}]},
                      'rpe':{'anyOf':[{'type':'number'},{'type':'null'}]},
                      'rir':{'anyOf':[{'type':'number'},{'type':'null'}]},
                      'scheme':{'type':'string'},
                    },
                    'required':['weight','reps','percentage','rpe','rir','scheme'],
                  }},
                },
                'required':['name','sets'],
              }},
            },
            'required':['name','exercises'],
          }},
        },
        'required':['number','days'],
      }},
      'warnings':{'type':'array','items':{'type':'string'}},
      'missing_data':{'type':'array','items':{'type':'string'}},
    },
    'required':['name','weeks','warnings','missing_data'],
  };

  Future<Map<String,dynamic>> analyzeText(String source) async {
    final instruction=_instruction() + '\n\nИСТОЧНИК:\n' + source;
    return _request([{ 'type':'input_text','text':instruction }]);
  }

  Future<Map<String,dynamic>> analyzeImage(Uint8List bytes,{String mimeType='image/jpeg'}) async {
    final b64=base64Encode(bytes);
    final prompt=_instruction() + '\n\nЭто фотография программы тренировок. Прочитай все видимые строки и таблицы. Не придумывай отсутствующие значения.';
    return _request([
      {'type':'input_text','text':prompt},
      {'type':'input_image','detail':'high','image_url':'data:' + mimeType + ';base64,' + b64},
    ]);
  }

  String _instruction() => '''Ты — модуль структурированного импорта программ силовых тренировок. Преобразуй источник в точную структуру программы.
Не исправляй программу по своему вкусу и не добавляй упражнения или веса, которых нет в источнике.
Сохраняй порядок недель, дней, упражнений и подходов.
Распознавай обозначения 5x5, 4x8, 3xAMRAP, @75%, RPE 8, RIR 2.
Если вес, процент, повторения, RPE или RIR не указаны, возвращай null.
Для сетов форматируй каждый фактически заданный подход отдельным объектом.
warnings и missing_data используй для сомнительных или неполных мест.
Отдельно различай тренировочную неделю и тренировочный день.
Название упражнения должно быть максимально близко к исходному тексту.''';

  Future<Map<String,dynamic>> _request(List<Map<String,dynamic>> userContent) async {
    final key=await apiKey();
    if(key==null||key.trim().isEmpty) throw StateError('Не задан OpenAI API key. Откройте настройки AI.');
    final url=Uri.parse((await baseUrl()).replaceFirst(RegExp(r'/+$'), '') + '/responses');
    final body={
      'model':await model(),
      'input':[{'role':'user','content':userContent}],
      'text':{'format':{'type':'json_schema','name':'workout_program','strict':true,'schema':schema}},
      'max_output_tokens':10000,
    };
    final response=await http.post(url,headers:{'Authorization':'Bearer ' + key.trim(),'Content-Type':'application/json'},body:jsonEncode(body));
    if(response.statusCode<200||response.statusCode>=300){
      throw StateError('AI API ${response.statusCode}: ${response.body.length>400?response.body.substring(0,400):response.body}');
    }
    final decoded=jsonDecode(utf8.decode(response.bodyBytes)) as Map<String,dynamic>;
    String? outputText;
    if(decoded['output_text'] is String) outputText=decoded['output_text'] as String;
    if(outputText==null && decoded['output'] is List){
      final chunks=<String>[];
      for(final item in decoded['output'] as List){
        if(item is Map && item['content'] is List){
          for(final part in item['content'] as List){
            if(part is Map && part['type']=='output_text' && part['text'] is String) chunks.add(part['text'] as String);
          }
        }
      }
      outputText=chunks.join();
    }
    if(outputText==null||outputText.trim().isEmpty) throw StateError('AI не вернул структурированный результат.');
    return jsonDecode(outputText) as Map<String,dynamic>;
  }
}