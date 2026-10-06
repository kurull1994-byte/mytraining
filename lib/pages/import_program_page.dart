import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../data/database.dart';
import '../services/program_source_reader.dart';
import '../services/training_text_parser.dart';

class ImportProgramPage extends StatefulWidget {
  final AppDatabase db;
  const ImportProgramPage({super.key, required this.db});
  @override State<ImportProgramPage> createState()=>_ImportProgramPageState();
}
class _ImportProgramPageState extends State<ImportProgramPage> {
  final text=TextEditingController();
  Uint8List? imageBytes; String? imageName; DraftProgram? draft; bool busy=false;
  @override void dispose(){text.dispose();super.dispose();}

  Future<void> pasteClipboard() async {
    final data=await Clipboard.getData(Clipboard.kTextPlain);
    if(data?.text==null||data!.text!.trim().isEmpty){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('В буфере нет текста')));
      return;
    }
    text.text=data!.text; parseText();
  }

  void parseText(){
    final source=text.text.trim();
    if(source.isEmpty)return;
    setState(()=>draft=TrainingTextParser.parse(source));
  }

  Future<void> pickFile() async {
    setState(()=>busy=true);
    try {
      final result=await FilePicker.platform.pickFiles(withData:true,type:FileType.custom,allowedExtensions:['txt','csv','xlsx','docx']);
      if(result==null||result.files.single.bytes==null)return;
      final file=result.files.single; final bytes=file.bytes!; final ext=(file.extension??'').toLowerCase();
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
    imageBytes=await photo.readAsBytes(); imageName=photo.name;
    if(mounted)setState(()=>{});
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
      Text('Источник программы',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w800)),
      const SizedBox(height:12),
      Wrap(spacing:8,runSpacing:8,children:[
        FilledButton.icon(onPressed:pasteClipboard,icon:const Icon(Icons.content_paste),label:const Text('Вставить из буфера')),
        OutlinedButton.icon(onPressed:busy?null:pickFile,icon:const Icon(Icons.attach_file),label:const Text('Excel / Word / TXT')),
        OutlinedButton.icon(onPressed:busy?null()=>takePhoto(ImageSource.camera),icon:const Icon(Icons.photo_camera_outlined),label:const Text('Сканировать')),
        OutlinedButton.icon(onPressed:busy?null()=>takePhoto(ImageSource.gallery),icon:const Icon(Icons.photo_library_outlined),label:const Text('Фото из галереи')),
      ]),
      const SizedBox(height:16),
      if(imageBytes!=null)Card(child:Padding(padding:const EdgeInsets.all(8),child:Column(children:[Image.memory(imageBytes!,height:220,fit:BoxFit.contain),const SizedBox(height:8),const Text('Фото программы подготовлено. Для точного распознавания фото в следующей итерации будет подключён AI Gateway.'),]))),
      const SizedBox(height:8),
      TextField(controller:text,minLines:10,maxLines:20,decoration:const InputDecoration(border:OutlineInputBorder(),labelText:'Текст программы',hintText:'Присед 5x5 @75%\nЖим 4x8 RPE 8\nНеделя 2\n...')),
      const SizedBox(height:10),
      FilledButton.icon(onPressed:busy?null:parseText,icon:const Icon(Icons.auto_fix_high),label:const Text('Разобрать программу')),
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