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
      'weeks':{
        'type':'array',
        'items':{
          'type':'object',
          'additionalProperties':false,
          'properties':{
            'number':{'type':'integer'},
            'days':{
              'type':'array',
              'items':{
                'type':'object',
                'additionalProperties':false,
                'properties':{
                  'name':{'type':'string'},
                  'exercises':{
                    'type':'array',
                    'items':{
                      'type':'object',
                      'additionalProperties':false,
                      'properties':{
                        'name':{'type':'string'},
                        'sets':{
                          'type':'array',
                          'items':{
                            'type':'object',
                            'additionalProperties':false,
                            'properties':{
                              'weight':{'anyOf':[{'type':'number'},{'type':'null'}]},
                              'reps':{'anyOf':[{'type':'integer'},{'type':'null'}]},
                              'percentage':{'anyOf':[{'type':'number'},{'type':'null'}]},
                              'rpe':{'anyOf':[{'type':'number'},{'type':'null'}]},
                              'rir':{'anyOf':[{'type':'number'},{'type':'null'}]},
                              'scheme':{'type':'string'},
                            },
                            'required':['weight','reps','percentage','rpe','rir','scheme'],
                          },
                        },
                      },
                      'required':['name','sets'],
                    },
                  },
                },
                'required':['name','exercises'],
              },
            },
          },
          'required':['number','days'],
        },
      },
      'warnings':{'type':'array','items':{'type':'string'}},
      'missing_data':{'type':'array','items':{'type':'string'}},
      'clarifications':{
        'type':'array',
        'items':{
          'type':'object',
          'additionalProperties':false,
          'properties':{
            'id':{'type':'string'},
            'question':{'type':'string'},
            'context':{'type':'string'},
            'options':{'type':'array','items':{'type':'string'}},
          },
          'required':['id','question','context','options'],
        },
      },
    },
    'required':['name','weeks','warnings','missing_data','clarifications'],
  };
  Future<Map<String,dynamic>> analyzeText(String source) async {
    final instruction=_instruction() + '\n\nИСТОЧНИК:\n' + source;
    return _request([{ 'type':'input_text','text':instruction }]);
  }

  Future<Map<String,dynamic>> refineText(
    String source,
    Map<String,dynamic> recognized,
    Map<String,String> answers,
  ) async {
    final content=[{
      'type':'input_text',
      'text':_instruction() +
          '\n\nИСХОДНЫЙ ТЕКСТ:\n' + source +
          '\n\nПРЕДВАРИТЕЛЬНОЕ РАСПОЗНАВАНИЕ:\n' + jsonEncode(recognized) +
          '\n\nОТВЕТЫ ПОЛЬЗОВАТЕЛЯ НА УТОЧНЕНИЯ:\n' + jsonEncode(answers) +
          '\n\nПересобери итоговую программу с учётом ответов. Сохрани все уже уверенно распознанные данные без изменений. Уточнения, на которые получен ответ, больше не считай неоднозначными.',
    }];
    return _request(content);
  }

  Future<Map<String,dynamic>> refineImages(
    List<Uint8List> images,
    Map<String,dynamic> recognized,
    Map<String,String> answers,
  ) async {
    if(images.isEmpty) throw StateError('Нет изображений для уточнения.');
    final content=<Map<String,dynamic>>[{
      'type':'input_text',
      'text':_instruction() +
          '\n\nПРЕДВАРИТЕЛЬНОЕ РАСПОЗНАВАНИЕ:\n' + jsonEncode(recognized) +
          '\n\nОТВЕТЫ ПОЛЬЗОВАТЕЛЯ НА УТОЧНЕНИЯ:\n' + jsonEncode(answers) +
          '\n\nПовторно проверь страницы по ответам пользователя. Сохрани уверенно распознанные данные. Исправь только неоднозначные места.',
    }];
    for(var i=0;i<images.length;i++){
      content.add({
        'type':'input_image',
        'detail':'high',
        'image_url':'data:image/jpeg;base64,'+base64Encode(images[i]),
      });
    }
    return _request(content);
  }

  Future<Map<String,dynamic>> analyzeImage(Uint8List bytes,{String mimeType='image/jpeg'}) async {
    return analyzeImages([bytes], mimeTypes:[mimeType]);
  }

  Future<Map<String,dynamic>> analyzeImages(
    List<Uint8List> images, {
    List<String>? mimeTypes,
  }) async {
    if (images.isEmpty) throw StateError('Нет изображений для распознавания.');
    if (images.length > 4) throw StateError('За один раз можно распознать не более 4 страниц.');
    final content=<Map<String,dynamic>>[
      {
        'type':'input_text',
        'text':_instruction() +
            '\n\nЭто одна или несколько фотографий страниц программы тренировок. ' +
            'Прочитай все видимые строки и таблицы. Объедини страницы в одну программу, ' +
            'сохраняя порядок страниц. Не придумывай отсутствующие значения.',
      },
    ];
    for (var i=0;i<images.length;i++) {
      final mime=(mimeTypes!=null && i<mimeTypes.length) ? mimeTypes[i] : 'image/jpeg';
      content.add({
        'type':'input_image',
        'detail':'high',
        'image_url':'data:' + mime + ';base64,' + base64Encode(images[i]),
      });
    }
    return _request(content);
  }

  String _instruction() => '''Ты — модуль структурированного импорта программ силовых тренировок. Преобразуй источник в точную структуру программы.
Не исправляй программу по своему вкусу и не добавляй упражнения или веса, которых нет в источнике.
Сохраняй порядок недель, дней, упражнений и подходов.
Распознавай обозначения 5x5, 4x8, 3xAMRAP, @75%, RPE 8, RIR 2.
Если вес, процент, повторения, RPE или RIR не указаны, возвращай null.
Для сетов форматируй каждый фактически заданный подход отдельным объектом.
warnings и missing_data используй для сомнительных или неполных мест.
Отдельно различай тренировочную неделю и тренировочный день.
Название упражнения должно быть максимально близко к исходному тексту.
Если источник — таблица вида «Упражнение | Нед1 | Нед2 | ... | Нед8», каждая строка упражнения должна быть распределена по всем соответствующим неделям, а не объединяться в один день. Запись «60×10, 3» означает: вес 60 кг, 10 повторений, 3 подхода. Запись «2×8» без веса означает: 2 подхода по 8 повторений. Запись «3×45с» означает: 3 подхода по 45 секунд. Число после запятой в ячейке — количество подходов, если это подтверждается контекстом таблицы. Для каждой недели создавай отдельные set-объекты и сохраняй исходный scheme.
Если любой фрагмент источника можно понять более чем одним способом или таблица/OCR неоднозначны, НЕ УГАДЫВАЙ: добавь clarifications с точным вопросом, контекстом строки/ячейки и 2–4 вариантами ответа. Сомнительный фрагмент пометь warning или missing_data.''';

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