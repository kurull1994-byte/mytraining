import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../data/database.dart';
import '../services/program_source_reader.dart';
import '../services/training_text_parser.dart';
import '../services/ai_gateway.dart';
import 'ai_settings_page.dart';

class ImportProgramPage extends StatefulWidget {
  final AppDatabase db;
  const ImportProgramPage({super.key, required this.db});
  @override State<ImportProgramPage> createState()=>_ImportProgramPageState();
}
class _ImportProgramPageState extends State<ImportProgramPage> {
  final text=TextEditingController();
  Uint8List? imageBytes;
  String? imageName;
  final List<Uint8List> scanPages=[];
  DraftProgram? draft;
  bool busy=false;
  final ai=AiGateway();
  @override void dispose(){text.dispose();super.dispose();}

  Future<void> pasteClipboard() async {
    final data=await Clipboard.getData(Clipboard.kTextPlain);
    final clipboardText = data?.text?.trim();
    if(clipboardText == null || clipboardText.isEmpty){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('В буфере нет текста')));
      return;
    }
    text.text=clipboardText; parseText();
  }

  void parseText(){
    final source=text.text.trim();
    if(source.isEmpty)return;
    setState(()=>draft=TrainingTextParser.parse(source));
  }

  Future<void> pickFile() async {
    setState(()=>busy=true);
    try {
      final file=await FilePicker.pickFile(type:FileType.custom,allowedExtensions:['txt','csv','xlsx','docx']);
      if(file==null)return;
      final bytes=await file.readAsBytes();
      final ext=(file.extension??'').toLowerCase();
      String extracted;
      if(ext=='xlsx')extracted=ProgramSourceReader.fromSpreadsheet(bytes);
      else if(ext=='docx')extracted=ProgramSourceReader.fromDocx(bytes);
      else extracted=String.fromCharCodes(bytes);
      text.text=extracted; parseText();
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Импортирован файл: '+file.name)));
    } finally { if(mounted)setState(()=>busy=false); }
  }

  Future<void> takePhoto(ImageSource source) async {
    final picker=ImagePicker();
    final photo=await picker.pickImage(source:source,maxWidth:2200,imageQuality:90);
    if(photo==null)return;
    final bytes=await photo.readAsBytes();
    imageBytes=bytes;
    imageName=photo.name;
    if(source==ImageSource.camera) {
      scanPages..clear()..add(bytes);
    }
    if(mounted)setState(() {});
  }

  Future<void> pickScanPages() async {
    final picker=ImagePicker();
    final photos=await picker.pickMultiImage(maxWidth:2200,imageQuality:90);
    if(photos.isEmpty)return;
    final pages=<Uint8List>[];
    for(final photo in photos.take(4)) {
      pages.add(await photo.readAsBytes());
    }
    scanPages..clear()..addAll(pages);
    imageBytes=pages.first;
    imageName=pages.length==1 ? photos.first.name : pages.length.toString() + ' страниц';
    if(mounted)setState(() {});
  }

  void clearScan() {
    scanPages.clear();
    imageBytes=null;
    imageName=null;
    draft=null;
    if(mounted)setState(() {});
  }
  Future<void> openAiSettings() async { await Navigator.push(context,MaterialPageRoute(builder:(_)=>const AiSettingsPage())); if(mounted)setState((){}); }

  Future<void> aiParseText() async {
    if(text.text.trim().isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Введите или вставьте программу')));return;}
    setState(()=>busy=true);
    try { final json=await ai.analyzeText(text.text.trim()); final d=TrainingTextParser.fromAiJson(json); if(mounted)setState(()=>draft=d); }
    catch(e){ if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString()))); }
    finally{if(mounted)setState(()=>busy=false);}
  }

  Future<void> aiParseImage() async {
    final pages=scanPages.isNotEmpty
        ? List<Uint8List>.from(scanPages)
        : (imageBytes==null ? <Uint8List>[] : <Uint8List>[imageBytes!]);
    if(pages.isEmpty){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Сначала сделайте фото или выберите изображение')));
      return;
    }
    setState(()=>busy=true);
    try {
      final json=await ai.analyzeImages(pages);
      final d=TrainingTextParser.fromAiJson(json);
      if(mounted)setState(()=>draft=d);
    } catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));
    } finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> saveDraft() async {
    if(draft==null)return;
    setState(()=>busy=true);
    try {
      final id=await widget.db.saveImportedProgram(draft!);
      if(mounted){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Программа сохранена')));Navigator.pop(context,id);}
    } finally {if(mounted)setState(()=>busy=false);}
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Добавить программу')),
    body:ListView(padding:const EdgeInsets.fromLTRB(16,8,16,40),children:[
      Row(children:[Expanded(child:Text('Источник программы',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w800))),IconButton(onPressed:openAiSettings,tooltip:'Настройки AI',icon:const Icon(Icons.settings_outlined))]),
      const SizedBox(height:12),
      Wrap(spacing:8,runSpacing:8,children:[
        FilledButton.icon(onPressed:pasteClipboard,icon:const Icon(Icons.content_paste),label:const Text('Вставить из буфера')),
        OutlinedButton.icon(onPressed:busy?null:pickFile,icon:const Icon(Icons.attach_file),label:const Text('Excel / Word / TXT')),
        OutlinedButton.icon(onPressed: busy ? null : () => takePhoto(ImageSource.camera),icon:const Icon(Icons.photo_camera_outlined),label:const Text('Сканировать')),
        OutlinedButton.icon(onPressed: busy ? null : () => takePhoto(ImageSource.gallery),icon:const Icon(Icons.photo_library_outlined),label:const Text('Фото из галереи')),
      ]),
      const SizedBox(height:16),
      if(imageBytes!=null)Card(
        child:Padding(
          padding:const EdgeInsets.all(8),
          child:Column(children:[
            if(scanPages.length>1)
              SizedBox(
                height:86,
                child:ListView.separated(
                  scrollDirection:Axis.horizontal,
                  itemCount:scanPages.length,
                  separatorBuilder:(_,__)=>const SizedBox(width:8),
                  itemBuilder:(context,i)=>ClipRRect(
                    borderRadius:BorderRadius.circular(8),
                    child:Image.memory(scanPages[i],width:72,height:86,fit:BoxFit.cover),
                  ),
                ),
              )
            else
              Image.memory(imageBytes!,height:220,fit:BoxFit.contain),
            const SizedBox(height:8),
            Text(scanPages.length>1
              ? 'Страниц для распознавания: '+scanPages.length.toString()+'. AI объединит их в одну программу.'
              : 'Фото программы готово к AI-распознаванию.'),
            const SizedBox(height:8),
            Row(children:[
              Expanded(child:FilledButton.icon(onPressed:busy?null:aiParseImage,icon:const Icon(Icons.auto_awesome),label:Text(scanPages.length>1?'AI распознать страницы':'AI распознать фото'))),
              const SizedBox(width:8),
              IconButton(onPressed:busy?null:clearScan,tooltip:'Очистить',icon:const Icon(Icons.delete_outline)),
            ]),
          ]),
        ),
      ),
      const SizedBox(height:8),
      TextField(controller:text,minLines:10,maxLines:20,decoration:const InputDecoration(border:OutlineInputBorder(),labelText:'Текст программы',hintText:'Присед 5x5 @75%\nЖим 4x8 RPE 8\nНеделя 2\n...')),
      const SizedBox(height:10),
      Row(children:[Expanded(child:FilledButton.icon(onPressed:busy?null:parseText,icon:const Icon(Icons.auto_fix_high),label:const Text('Разобрать локально'))),const SizedBox(width:8),Expanded(child:FilledButton.icon(onPressed:busy?null:aiParseText,icon:const Icon(Icons.auto_awesome),label:const Text('AI распознать текст')))]),
      if(draft!=null)...[
        const SizedBox(height:18),
        Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(draft!.name,style:const TextStyle(fontSize:19,fontWeight:FontWeight.bold)),
          Text('Недель: '+draft!.weeks.length.toString()),
          const SizedBox(height:10),
          ...draft!.weeks.map((w)=>Padding(padding:const EdgeInsets.only(bottom:8),child:Text('Неделя '+w.number.toString()+' · дней: '+w.days.length.toString()))),
          if(draft!.warnings.isNotEmpty)Padding(padding:const EdgeInsets.only(top:8),child:Text('Предупреждения: '+draft!.warnings.join(' | '))),
          if(draft!.missingData.isNotEmpty)Padding(padding:const EdgeInsets.only(top:8),child:Text('Нужно проверить: '+draft!.missingData.join(' | '))),
        ]))),
        const SizedBox(height:10),
        FilledButton.icon(onPressed:busy?null:saveDraft,icon:const Icon(Icons.save),label:const Text('Сохранить программу и открыть редактор')),
      ],
    ]),
  );
}