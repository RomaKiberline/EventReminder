import 'package:flutter/material.dart';
import 'api_client.dart';

/// One login form for both registration and sign-in. No credentials persisted.
class ServerLoginScreen extends StatefulWidget {
  const ServerLoginScreen({super.key,required this.api,required this.onAuthenticated});
  final ApiClient api;
  final Future<void> Function() onAuthenticated;
  @override State<ServerLoginScreen> createState()=>_ServerLoginScreenState();
}

class _ServerLoginScreenState extends State<ServerLoginScreen> {
  final _formKey=GlobalKey<FormState>();
  final _email=TextEditingController();
  final _password=TextEditingController();
  bool _register=false;
  bool _busy=false;
  bool _obscure=true;
  String? _error;

  @override void dispose(){_email.dispose();_password.dispose();super.dispose();}

  Future<void> _submit() async {
    if(!_formKey.currentState!.validate() || _busy)return;
    setState((){_busy=true;_error=null;});
    try {
      if(_register){await widget.api.register(_email.text,_password.text);}
      else{await widget.api.login(_email.text,_password.text);}
      await widget.onAuthenticated();
    } catch(e) {
      if(mounted)setState(()=>_error=e.toString().replaceFirst('Bad state: ',''));
    } finally {if(mounted)setState(()=>_busy=false);}
  }

  @override Widget build(BuildContext context)=>Scaffold(
    body:SafeArea(child:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(24),
      child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:410),child:Form(
      key:_formKey,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        const Icon(Icons.cloud_sync_outlined,size:60,color:Color(0xFF788CF5)),
        const SizedBox(height:14),
        Text('Мої події — сервер',textAlign:TextAlign.center,
          style:Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height:8),
        Text(_register?'Створи обліковий запис для REST API':'Увійди до REST API',
          textAlign:TextAlign.center),
        const SizedBox(height:22),
        TextFormField(controller:_email,keyboardType:TextInputType.emailAddress,
          autofillHints:const [AutofillHints.email],decoration:const InputDecoration(labelText:'Email'),
          validator:(v)=>v==null||!v.contains('@')?'Введи коректний email':null),
        const SizedBox(height:14),
        TextFormField(controller:_password,obscureText:_obscure,
          decoration:InputDecoration(labelText:'Пароль',suffixIcon:IconButton(
            icon:Icon(_obscure?Icons.visibility:Icons.visibility_off),
            onPressed:()=>setState(()=>_obscure=!_obscure))),
          validator:(v)=>v==null||v.isEmpty?'Введи пароль'
            :_register&&v.length<8?'Для реєстрації потрібно мінімум 8 символів':null,
          onFieldSubmitted:(_)=>_submit()),
        if(_error!=null)...[
          const SizedBox(height:14),
          Text(_error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height:20),
        FilledButton(onPressed:_busy?null:_submit,
          child:Padding(padding:const EdgeInsets.all(12),
            child:_busy?const SizedBox(height:19,width:19,child:CircularProgressIndicator(strokeWidth:2))
              :Text(_register?'Зареєструватися':'Увійти'))),
        TextButton(onPressed:_busy?null:()=>setState((){_register=!_register;_error=null;}),
          child:Text(_register?'Вже є обліковий запис? Увійти':'Новий користувач? Реєстрація')),
      ]))))),
    ),
  );
}
