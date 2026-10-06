import 'package:flutter/material.dart';
import '../services/ai_gateway.dart';

class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});
  @override State<AiSettingsPage> createState()=>_AiSettingsPageState();
}
class _AiSettingsPageState extends State<AiSettingsPage> {
  final gateway=AiGateway();
  final key=TextEditingController();
  final base=TextEditingController(text:'https://api.openai.com/v1');
  final model=TextEditingController(text:'gpt-6-luna');
  bool obscure=true;
  bool loading=true;
  @override void initState(){super.initState();load();}
  @override void dispose(){key.dispose();base.dispose();model.dispose();super.dispose();}
  Future<void> load() async { key.text=await gateway.apiKey() ?? ''; base.text=await gateway.baseUrl(); model.text=await gateway.model(); if(mounted)setState(()=>loading=false); }
  Future<void> save() async { await gateway.saveSettings(apiKey:key.text,baseUrl:base.text,model:model.text); if(mounted){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Настройки AI сохранены')));Navigator.pop(context);}}
  @override Widget build(BuildContext context){
    if(loading)return const Scaffold(body:Center(child:CircularProgressIndicator()));
    return Scaffold(appBar:AppBar(title:const Text('AI и импорт')),body:ListView(padding:const EdgeInsets.all(16),children:[
      const Text('Для AI-распознавания нужен API-ключ. Ключ хранится на устройстве в защищённом хранилище.',style:TextStyle(height:1.4)),
      const SizedBox(height:16),
      TextField(controller:key,obscureText:obscure,decoration:InputDecoration(labelText:'OpenAI API key',suffixIcon:IconButton(onPressed:()=>setState(()=>obscure=!obscure),icon:Icon(obscure?Icons.visibility:Icons.visibility_off)))),
      const SizedBox(height:10),
      TextField(controller:model,decoration:const InputDecoration(labelText:'Модель',helperText:'По умолчанию: gpt-6-luna')),
      const SizedBox(height:10),
      TextField(controller:base,decoration:const InputDecoration(labelText:'AI Gateway URL',helperText:'По умолчанию https://api.openai.com/v1')),
      const SizedBox(height:18),
      FilledButton.icon(onPressed:save,icon:const Icon(Icons.save),label:const Text('Сохранить настройки')),
      const SizedBox(height:20),
      const Card(child:Padding(padding:EdgeInsets.all(14),child:Text('AI используется для распознавания текста и фотографий. Перед записью в программу результат показывается для проверки и редактирования. Не передавайте API-ключ другим людям.'))),
    ]));
  }
}