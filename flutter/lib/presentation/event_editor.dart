import 'package:flutter/material.dart';
import '../application/app_controller.dart';
import '../domain/models.dart';
import 'ui_helpers.dart';

/// A validated event form. An individual recurrence instance can change
/// its title/time only, matching the event_exceptions table in Lab #5.
class EventEditor extends StatefulWidget {
  final AppController controller;
  final EventItem? existing;
  final EventOccurrence? oneInstance;
  final DateTime? suggestedStart;
  const EventEditor({super.key,required this.controller,this.existing,
    this.oneInstance,this.suggestedStart});
  @override
  State<EventEditor> createState()=>_EventEditorState();
}

class _EventEditorState extends State<EventEditor> {
  final _formKey=GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _location;
  late final TextEditingController _interval;
  late final TextEditingController _count;
  DateTime _start=DateTime.now();
  DateTime? _end;
  int? _category;
  String _frequency='NONE';
  String _repeatEnd='never';
  DateTime? _until;
  Set<int> _weekdays={};
  Set<int> _reminders={};
  bool _saving=false;
  bool get single=>widget.oneInstance!=null;

  @override
  void initState() {
    super.initState();
    final event=widget.existing;
    final instance=widget.oneInstance;
    _title=TextEditingController(text:instance?.title ?? event?.title ?? '');
    _description=TextEditingController(text:event?.description ?? '');
    _location=TextEditingController(text:event?.location ?? '');
    _start=instance?.start ?? event?.start ?? widget.suggestedStart ?? DateTime.now().add(const Duration(hours:1));
    _end=instance?.end ?? event?.end;
    _category=event?.categoryId;
    _frequency=event?.recurrence?.frequency ?? 'NONE';
    _interval=TextEditingController(text:'${event?.recurrence?.interval ?? 1}');
    _count=TextEditingController(text:'${event?.recurrence?.count ?? 10}');
    _until=event?.recurrence?.until;
    _repeatEnd=event?.recurrence?.count!=null ? 'count' : event?.recurrence?.until!=null ? 'until' : 'never';
    _weekdays={...?event?.recurrence?.weekdays};
    _reminders={...?event?.reminderOffsets};
  }
  @override
  void dispose() {
    _title.dispose();_description.dispose();_location.dispose();
    _interval.dispose();_count.dispose();super.dispose();
  }

  Future<DateTime?> _chooseDateTime(DateTime base) async {
    final date=await showDatePicker(context:context,initialDate:base,
      firstDate:DateTime(2000),lastDate:DateTime(2100));
    if(date==null || !mounted) return null;
    final time=await showTimePicker(context:context,initialTime:TimeOfDay.fromDateTime(base));
    if(time==null) return null;
    return DateTime(date.year,date.month,date.day,time.hour,time.minute);
  }
  Future<void> _addCustomReminder() async {
    final controller=TextEditingController();
    final offset=await showDialog<int>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Власне нагадування'),
      content:TextField(controller:controller,keyboardType:TextInputType.number,
        decoration:const InputDecoration(labelText:'За скільки хвилин до події?')),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Скасувати')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,int.tryParse(controller.text)),child:const Text('Додати'))],
    ));
    controller.dispose();
    if(offset!=null && offset>=0 && offset<525600 && mounted) setState(()=>_reminders.add(offset));
  }
  Future<void> _save() async {
    if(!_formKey.currentState!.validate()) return;
    if(_end!=null && _end!.isBefore(_start)) {
      showMessage(context,'Час завершення не може бути раніше початку');return;
    }
    final interval=int.tryParse(_interval.text) ?? 0;
    if(!single && _frequency!='NONE' && (interval<1 || interval>365)) {
      showMessage(context,'Інтервал повторення має бути від 1 до 365');return;
    }
    if(!single && _frequency!='NONE' && _repeatEnd=='count' && (int.tryParse(_count.text) ?? 0)<1) {
      showMessage(context,'Введи кількість повторів');return;
    }
    if(!single && _frequency!='NONE' && _repeatEnd=='until' && (_until==null || _until!.isBefore(dayStart(_start)))) {
      showMessage(context,'Дата завершення повторень має бути не раніше початку');return;
    }
    setState(()=>_saving=true);
    try {
      if(single) {
        await widget.controller.editOccurrence(EventException(
          eventId:widget.oneInstance!.event.id!,
          originalStart:widget.oneInstance!.originalStart,type:'MODIFIED',
          overrideStart:_start,overrideEnd:_end,overrideTitle:_title.text.trim()));
      } else {
        final rule=_frequency=='NONE' ? null : RecurrenceRule(
          frequency:_frequency,interval:interval,
          until:_repeatEnd=='until' ? _until : null,
          count:_repeatEnd=='count' ? int.parse(_count.text) : null,
          weekdays:_frequency=='WEEKLY' ? (_weekdays.isEmpty ? [_start.weekday] : _weekdays.toList()..sort()) : [],
        );
        if(_reminders.isNotEmpty && widget.controller.notifications.supported &&
          widget.existing?.reminderOffsets.isEmpty != false) {
          final agree=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
            title:const Text('Дозвіл на сповіщення'),
            content:const Text('Щоб нагадувати про події навіть після закриття програми, '
              'потрібен дозвіл системи на сповіщення. Подія збережеться і без дозволу.'),
            actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Не зараз')),
              FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Дозволити'))],
          )) ?? false;
          if(agree) {
            try {await widget.controller.notifications.requestPermission();}
            catch (_) { /* Denied or unavailable permission must not block saving. */ }
          }
        }
        final item=EventItem(id:widget.existing?.id,title:_title.text.trim(),
          description:_description.text,location:_location.text,start:_start,end:_end,
          categoryId:_category,recurrence:rule,status:widget.existing?.status ?? 'PLANNED',
          reminderOffsets:_reminders.toList()..sort());
        await widget.controller.save(item);
      }
      if(mounted) Navigator.pop(context,true);
    } catch(e) { if(mounted) showFailure(context,e); }
    finally {if(mounted) setState(()=>_saving=false);}
  }

  @override
  Widget build(BuildContext context) {
    final labels={0:'Немає',5:'5 хв',15:'15 хв',30:'30 хв',60:'1 год',1440:'1 день'};
    final recurring=widget.existing?.recurrence!=null;
    return Dialog(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:610),
      child:Padding(padding:const EdgeInsets.fromLTRB(22,18,22,18),
        child:Form(key:_formKey,child:Column(mainAxisSize:MainAxisSize.min,
          crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[
            Expanded(child:Text(single?'Змінити одне повторення':widget.existing==null?'Нова подія':'Редагувати подію',
              style:Theme.of(context).textTheme.headlineSmall)),
            IconButton(onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.close)),
          ]),
          if(single) const Padding(padding:EdgeInsets.only(top:6),
            child:Text('Для окремого повторення можна змінити назву, дату та час. Інші поля належать усій серії.')),
          const SizedBox(height:12),
          Flexible(child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            TextFormField(controller:_title,autofocus:widget.existing==null,
              decoration:const InputDecoration(labelText:'Назва *',prefixIcon:Icon(Icons.edit_note)),
              validator:(v)=>v==null || v.trim().isEmpty ? 'Введи назву' :
                v.trim().length>150 ? 'Максимум 150 символів' : null),
            const SizedBox(height:12),
            Row(children:[
              Expanded(child:OutlinedButton.icon(icon:const Icon(Icons.event),
                label:Text('Початок: ${dateTimeText(_start)}'),
                onPressed:() async {final d=await _chooseDateTime(_start);
                  if(d!=null) setState((){final duration=_end?.difference(_start);
                    _start=d;_end=duration==null?null:d.add(duration);});})),
            ]),
            Row(children:[
              Expanded(child:OutlinedButton.icon(icon:const Icon(Icons.timer_outlined),
                label:Text(_end==null?'Завершення: не вказано':'Кінець: ${dateTimeText(_end!)}'),
                onPressed:() async {final d=await _chooseDateTime(_end ?? _start.add(const Duration(hours:1)));
                  if(d!=null) setState(()=>_end=d);})),
              if(_end!=null) IconButton(onPressed:()=>setState(()=>_end=null),
                tooltip:'Очистити час завершення',icon:const Icon(Icons.close)),
            ]),
            if(!single) ...[
              const SizedBox(height:12),
              TextField(controller:_description,maxLines:2,
                decoration:const InputDecoration(labelText:'Опис',prefixIcon:Icon(Icons.notes))),
              const SizedBox(height:12),
              TextField(controller:_location,
                decoration:const InputDecoration(labelText:'Місце',prefixIcon:Icon(Icons.place_outlined))),
              const SizedBox(height:12),
              DropdownButtonFormField<int?>(initialValue:_category,
                decoration:const InputDecoration(labelText:'Категорія',prefixIcon:Icon(Icons.label_outline)),
                items:[const DropdownMenuItem<int?>(value:null,child:Text('Без категорії')),
                  for(final c in widget.controller.categories) DropdownMenuItem<int?>(value:c.id,child:Text(c.name))],
                onChanged:(value)=>setState(()=>_category=value)),
              const SizedBox(height:18),
              Text('Повторення',style:Theme.of(context).textTheme.titleMedium),
              const SizedBox(height:8),
              DropdownButtonFormField<String>(initialValue:_frequency,
                items:const [DropdownMenuItem(value:'NONE',child:Text('Не повторюється')),
                  DropdownMenuItem(value:'DAILY',child:Text('Щодня')),
                  DropdownMenuItem(value:'WEEKLY',child:Text('Щотижня')),
                  DropdownMenuItem(value:'MONTHLY',child:Text('Щомісяця'))],
                onChanged:(v)=>setState(()=>_frequency=v ?? 'NONE')),
              if(_frequency!='NONE') ...[
                const SizedBox(height:8),
                TextField(controller:_interval,keyboardType:TextInputType.number,
                  decoration:const InputDecoration(labelText:'Повторювати кожні N днів / тижнів / місяців')),
                if(_frequency=='WEEKLY') ...[
                  const SizedBox(height:8),
                  Wrap(spacing:4,children:[for(var i=1;i<=7;i++)
                    FilterChip(label:Text(['Пн','Вт','Ср','Чт','Пт','Сб','Нд'][i-1]),
                      selected:_weekdays.contains(i),onSelected:(v)=>setState((){
                        if(v) {_weekdays.add(i);} else {_weekdays.remove(i);}
                      }))]),
                ],
                const SizedBox(height:8),
                DropdownButtonFormField<String>(initialValue:_repeatEnd,
                  decoration:const InputDecoration(labelText:'Завершення повторень'),
                  items:const [DropdownMenuItem(value:'never',child:Text('Без обмежень')),
                    DropdownMenuItem(value:'until',child:Text('До дати')),
                    DropdownMenuItem(value:'count',child:Text('Кількість повторів'))],
                  onChanged:(v)=>setState(()=>_repeatEnd=v ?? 'never')),
                if(_repeatEnd=='until') OutlinedButton.icon(
                  icon:const Icon(Icons.date_range),label:Text(_until==null?'Вибрати дату':dayText(_until!)),
                  onPressed:() async {final d=await showDatePicker(context:context,
                    firstDate:dayStart(_start),lastDate:DateTime(2100),
                    initialDate:_until!=null && !_until!.isBefore(dayStart(_start)) ? _until! : dayStart(_start));
                    if(d!=null)setState(()=>_until=d);}),
                if(_repeatEnd=='count') TextField(controller:_count,keyboardType:TextInputType.number,
                  decoration:const InputDecoration(labelText:'Кількість повторів')),
              ],
              const SizedBox(height:18),
              Text('Нагадування',style:Theme.of(context).textTheme.titleMedium),
              const SizedBox(height:8),
              Wrap(spacing:6,runSpacing:4,children:[
                for(final entry in labels.entries)
                  FilterChip(label:Text(entry.value),selected:_reminders.contains(entry.key),
                    onSelected:(selected)=>setState((){
                      if(selected){_reminders.add(entry.key);}else{_reminders.remove(entry.key);}
                    })),
                ActionChip(avatar:const Icon(Icons.add,size:17),label:const Text('Власне'),
                  onPressed:_addCustomReminder),
                for(final val in _reminders.where((x)=>!labels.containsKey(x)).toList())
                  InputChip(label:Text('$val хв'),onDeleted:()=>setState(()=>_reminders.remove(val))),
              ]),
              if(recurring) const Padding(padding:EdgeInsets.only(top:8),
                child:Text('Зміни всієї серії застосовуються до кожного повторення.')),
            ],
          ]))),
          const SizedBox(height:16),
          Row(mainAxisAlignment:MainAxisAlignment.end,children:[
            TextButton(onPressed:_saving?null:()=>Navigator.pop(context),child:const Text('Скасувати')),
            const SizedBox(width:8),
            FilledButton.icon(onPressed:_saving?null:_save,icon:const Icon(Icons.save_outlined),
              label:Text(_saving?'Збереження…':'Зберегти')),
          ]),
        ])))));
  }
}
