import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../application/app_controller.dart';
import '../domain/models.dart';
import '../infrastructure/backup_service.dart';
import '../network/api_event_repository.dart';
import 'event_editor.dart';
import 'ui_helpers.dart';

class AppShell extends StatefulWidget {
  final AppController controller;
  const AppShell({super.key,required this.controller});
  @override
  State<AppShell> createState()=>_AppShellState();
}

class _AppShellState extends State<AppShell> {
  int tab=0;
  late DateTime selectedDate;
  DateTime displayed=DateTime.now();
  String calendarMode='Місяць';
  bool dialogOpening=false;
  @override
  void initState() {
    super.initState(); selectedDate=dayStart(DateTime.now());
    widget.controller.addListener(_notificationListener);
  }
  @override
  void dispose() {widget.controller.removeListener(_notificationListener);super.dispose();}
  void _notificationListener() {
    if(!mounted || dialogOpening || widget.controller.pendingEvent==null || !widget.controller.ready) return;
    final id=widget.controller.pendingEvent!;
    widget.controller.clearPending();
    dialogOpening=true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if(mounted) {
        final event=widget.controller.findEvent(id);
        if(event!=null) {
          final now=DateTime.now();
          final all=widget.controller.between(now.subtract(const Duration(days:365)),
            now.add(const Duration(days:365)));
          final occurrences=all.where((x)=>x.event.id==id).toList();
          final item=occurrences.isNotEmpty ? occurrences.first : EventOccurrence(
            event:event,originalStart:event.start,start:event.start,end:event.end,
            title:event.title,status:event.status);
          await _openDetails(item);
        }
      }
      dialogOpening=false;
    });
  }
  Future<void> _newEvent([DateTime? when]) async {
    await showDialog<bool>(context:context,barrierDismissible:false,
      builder:(_)=>EventEditor(controller:widget.controller,
        suggestedStart:when ?? (sameDay(selectedDate,DateTime.now())
          ? DateTime.now().add(const Duration(hours:1))
          : selectedDate.add(const Duration(hours:9)))));
  }
  Future<void> _openDetails(EventOccurrence item) async {
    await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
      title:Row(children:[
        Expanded(child:Text(item.title)),
        IconButton(onPressed:()=>Navigator.pop(ctx),icon:const Icon(Icons.close)),
      ]),
      content:ConstrainedBox(constraints:const BoxConstraints(maxWidth:440),
        child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,
          crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(dateTimeText(item.start),style:Theme.of(ctx).textTheme.titleMedium),
          if(item.end!=null) Text('До ${dateTimeText(item.end!)}'),
          const SizedBox(height:8),
          if(item.event.description.isNotEmpty) Text(item.event.description),
          if(item.event.location.isNotEmpty) Padding(padding:const EdgeInsets.only(top:8),
            child:Text('📍 ${item.event.location}')),
          if(widget.controller.categoryOf(item.event.categoryId)!=null)
            Padding(padding:const EdgeInsets.only(top:8),child:Chip(label:Text(
              widget.controller.categoryOf(item.event.categoryId)!.name))),
          if(item.event.recurrence!=null) const Text('↻ Повторювана подія'),
          const SizedBox(height:8),
          Text('Статус: ${statusText(item.status)}'),
        ]))),
      actionsAlignment:MainAxisAlignment.spaceBetween,
      actions:[
        PopupMenuButton<String>(tooltip:'Дії з подією',icon:const Icon(Icons.more_horiz),
          onSelected:(action) async {
            Navigator.pop(ctx);
            try {
              if(action=='delete') {await _askDelete(item);return;}
              if(action=='DONE'||action=='MISSED'||action=='PLANNED') {
                await widget.controller.changeStatus(item,action);
                if(mounted) showMessage(context,'Статус оновлено');
              }
            } catch(e) {if(mounted) showFailure(context,e);}
          },itemBuilder:(_)=>[
            const PopupMenuItem(value:'DONE',child:Text('Позначити виконаною')),
            const PopupMenuItem(value:'MISSED',child:Text('Позначити пропущеною')),
            const PopupMenuItem(value:'PLANNED',child:Text('Повернути в заплановані')),
            const PopupMenuDivider(),
            const PopupMenuItem(value:'delete',child:Text('Видалити')),
          ]),
        FilledButton.tonalIcon(onPressed:() async {
          Navigator.pop(ctx);await _askEdit(item);
        },icon:const Icon(Icons.edit_outlined),label:const Text('Редагувати')),
      ],
    ));
  }
  Future<bool?> _askScope(String operation) async => showDialog<bool>(context:context,
    builder:(ctx)=>AlertDialog(title:Text(operation),
      content:const Text('Застосувати зміну тільки до цього входження чи до всієї серії?'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Скасувати')),
        TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Лише це')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Уся серія'))]));
  Future<void> _askEdit(EventOccurrence occ) async {
    final whole=occ.event.recurrence==null ? true : await _askScope('Редагування повторення');
    if(whole==null || !mounted) return;
    await showDialog<bool>(context:context,barrierDismissible:false,
      builder:(_)=>EventEditor(controller:widget.controller,existing:occ.event,
        oneInstance:whole?null:occ));
  }
  Future<void> _askDelete(EventOccurrence occ) async {
    final whole=occ.event.recurrence==null ? true : await _askScope('Видалення повторення');
    if(whole==null || !mounted) return;
    final accepted=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Підтвердити видалення'),
      content:Text(whole?'Видалити «${occ.title}» разом із пов’язаними нагадуваннями?'
        :'Видалити тільки вибране повторення «${occ.title}»?'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Скасувати')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Видалити'))]));
    if(accepted!=true || !mounted) return;
    try {await widget.controller.deleteOccurrence(occ,wholeSeries:whole);
      if(mounted) showMessage(context,'Подію видалено');}
    catch(e) {if(mounted) showFailure(context,e);}
  }

  @override
  Widget build(BuildContext context) {
    final ctrl=widget.controller;
    final menus=<({IconData icon,IconData filled,String label})>[
      (icon:Icons.home_outlined,filled:Icons.home,label:'Головна'),
      (icon:Icons.calendar_month_outlined,filled:Icons.calendar_month,label:'Календар'),
      (icon:Icons.search,filled:Icons.manage_search,label:'Пошук'),
      (icon:Icons.label_outline,filled:Icons.label,label:'Категорії'),
      (icon:Icons.settings_outlined,filled:Icons.settings,label:'Налаштування'),
    ];
    return LayoutBuilder(builder:(ctx,limits){
      final wide=limits.maxWidth>=860;
      final panels=<Widget>[
        _home(ctrl),_calendar(ctrl),_search(ctrl),_categories(ctrl),_settings(ctrl),
      ];
      final content=Column(children:[
        Container(padding:EdgeInsets.symmetric(horizontal:wide?28:16,vertical:14),
          child:Row(children:[
            Icon(Icons.event_available,color:Theme.of(context).colorScheme.primary,size:27),
            const SizedBox(width:10),
            Text('Мої події',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w800)),
            const Spacer(),
            IconButton(tooltip:'Сьогодні',onPressed:()=>setState((){
              selectedDate=dayStart(DateTime.now());displayed=DateTime.now();tab=1;}),
              icon:const Icon(Icons.today_outlined)),
            FilledButton.icon(onPressed:()=>_newEvent(),icon:const Icon(Icons.add),
              label:Text(wide?'Додати подію':'Додати')),
          ])),
        const Divider(height:1),
        Expanded(child:!ctrl.ready
          ? const Center(child:CircularProgressIndicator())
          : ctrl.error!=null
            ? EmptyState(icon:Icons.error_outline,title:'Помилка запуску',subtitle:ctrl.error!)
            : panels[tab]),
      ]);
      return Scaffold(
        body:SafeArea(child:Row(children:[
          if(wide) NavigationRail(selectedIndex:tab,
            onDestinationSelected:(v)=>setState(()=>tab=v),
            labelType:NavigationRailLabelType.all,
            destinations:[for(final m in menus) NavigationRailDestination(
              icon:Icon(m.icon),selectedIcon:Icon(m.filled),label:Text(m.label))]),
          if(wide) const VerticalDivider(width:1),
          Expanded(child:content),
        ])),
        bottomNavigationBar:wide?null:NavigationBar(selectedIndex:tab,
          onDestinationSelected:(v)=>setState(()=>tab=v),
          destinations:[for(final m in menus) NavigationDestination(
            icon:Icon(m.icon),selectedIcon:Icon(m.filled),label:m.label)]),
      );
    });
  }

  Widget _sectionTitle(String title,[String? hint])=>Padding(
    padding:const EdgeInsets.only(top:8,bottom:14),child:Column(
    crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(title,style:Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight:FontWeight.bold)),
      if(hint!=null) Padding(padding:const EdgeInsets.only(top:4),
        child:Text(hint,style:Theme.of(context).textTheme.bodyMedium)),
    ]));

  Widget _home(AppController ctrl) {
    final now=DateTime.now();
    final upcoming=ctrl.between(now,now.add(const Duration(days:90)))
      .where((x)=>x.status=='PLANNED').take(40).toList();
    final today=ctrl.between(dayStart(now),dayEnd(now));
    final done=today.where((x)=>x.status=='DONE').length;
    final all=ctrl.between(now.subtract(const Duration(days:365)),now.add(const Duration(days:365)));
    return ListView(padding:const EdgeInsets.symmetric(horizontal:18,vertical:10),children:[
      Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:980),child:Column(
        crossAxisAlignment:CrossAxisAlignment.start,children:[
        _sectionTitle('Твій план на сьогодні',DateFormat('EEEE, d MMMM yyyy','uk').format(now)),
        Wrap(spacing:10,runSpacing:10,children:[
          _metric('Сьогодні','${today.length}',Icons.today),
          _metric('Виконано','${done}',Icons.check_circle_outline),
          _metric('Заплановано','${all.where((e)=>e.status=='PLANNED').length}',Icons.event_note),
        ]),
        const SizedBox(height:20),
        Row(children:[
          Expanded(child:Text('Найближчі події',style:Theme.of(context).textTheme.titleLarge)),
          TextButton(onPressed:()=>setState(()=>tab=1),child:const Text('Календар →')),
        ]),
        if(upcoming.isEmpty) Padding(padding:const EdgeInsets.symmetric(vertical:55),
          child:EmptyState(icon:Icons.event_available,title:'Поки немає майбутніх подій',
            subtitle:'Натисни «Додати подію», щоб запланувати свою першу справу.')),
        for(final occ in upcoming) EventTile(occurrence:occ,category:ctrl.categoryOf(occ.event.categoryId),
          onTap:()=>_openDetails(occ)),
      ]))),
    ]);
  }
  Widget _metric(String label,String value,IconData icon)=>Container(
    width:190,padding:const EdgeInsets.all(16),
    decoration:BoxDecoration(color:Theme.of(context).colorScheme.primaryContainer.withValues(alpha:.35),
      borderRadius:BorderRadius.circular(20)),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Icon(icon,color:Theme.of(context).colorScheme.primary),const SizedBox(height:9),
      Text(value,style:Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight:FontWeight.w800)),
      Text(label),
    ]));

  Widget _calendar(AppController ctrl) {
    final start=calendarMode=='Місяць'
      ? DateTime(displayed.year,displayed.month)
      : calendarMode=='Тиждень'
        ? dayStart(selectedDate.subtract(Duration(days:selectedDate.weekday-1)))
        : dayStart(selectedDate);
    final end=calendarMode=='Місяць'
      ? DateTime(displayed.year,displayed.month+1)
      : calendarMode=='Тиждень' ? start.add(const Duration(days:7)) : dayEnd(start);
    final occurrences=ctrl.between(start,end);
    void move(int direction) =>setState((){
      if(calendarMode=='Місяць') {
        displayed=DateTime(displayed.year,displayed.month+direction);
        selectedDate=DateTime(displayed.year,displayed.month,1);
      } else {
        selectedDate=selectedDate.add(Duration(days:direction*(calendarMode=='Тиждень'?7:1)));
        displayed=selectedDate;
      }
    });
    return ListView(padding:const EdgeInsets.all(16),children:[
      Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:980),child:Column(
        crossAxisAlignment:CrossAxisAlignment.start,children:[
        _sectionTitle('Календар','Перегляд подій за день, тиждень або місяць'),
        Wrap(spacing:8,runSpacing:8,children:[for(final mode in ['День','Тиждень','Місяць'])
          ChoiceChip(label:Text(mode),selected:calendarMode==mode,
            onSelected:(_)=>setState(()=>calendarMode=mode))]),
        const SizedBox(height:14),
        Row(children:[IconButton(onPressed:()=>move(-1),icon:const Icon(Icons.chevron_left)),
          Expanded(child:Text(calendarMode=='Місяць'
            ? DateFormat('LLLL yyyy','uk').format(displayed)
            : calendarMode=='Тиждень' ? '${dateText(start)} — ${dateText(end.subtract(const Duration(days:1)))}'
              :dayText(selectedDate),
            textAlign:TextAlign.center,style:Theme.of(context).textTheme.titleLarge)),
          IconButton(onPressed:()=>move(1),icon:const Icon(Icons.chevron_right))]),
        if(calendarMode=='Місяць') _monthGrid(ctrl) else if(calendarMode=='Тиждень')
          _weekList(ctrl,start,end) else _dayList(ctrl,selectedDate),
        if(calendarMode=='Місяць') ...[
          const SizedBox(height:18),
          Text('Події: ${dayText(selectedDate)}',style:Theme.of(context).textTheme.titleMedium),
          _dayItems(ctrl,selectedDate),
        ],
      ]))),
    ]);
  }
  Widget _monthGrid(AppController ctrl) {
    final first=DateTime(displayed.year,displayed.month,1);
    final last=DateTime(displayed.year,displayed.month+1,0);
    final offset=first.weekday-1;
    final days=((offset+last.day+6)~/7)*7;
    final countByDay=<int,List<EventOccurrence>>{};
    for(final occurrence in ctrl.between(first,DateTime(first.year,first.month+1))) {
      (countByDay[occurrence.start.day]??=[]).add(occurrence);
    }
    return Card(child:Padding(padding:const EdgeInsets.all(10),child:Column(children:[
      Row(children:[for(final label in ['Пн','Вт','Ср','Чт','Пт','Сб','Нд'])
        Expanded(child:Center(child:Padding(padding:const EdgeInsets.symmetric(vertical:10),
          child:Text(label,style:const TextStyle(fontWeight:FontWeight.w600)))))]),
      GridView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),
        gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount:7,childAspectRatio:.95,crossAxisSpacing:3,mainAxisSpacing:3),
        itemCount:days,itemBuilder:(ctx,i){
          final day=i-offset+1;
          if(day<1 || day>last.day) return const SizedBox.shrink();
          final d=DateTime(first.year,first.month,day);
          final isToday=sameDay(d,DateTime.now());
          final selected=sameDay(d,selectedDate);
          final items=countByDay[day] ?? [];
          return InkWell(borderRadius:BorderRadius.circular(12),
            onTap:()=>setState(()=>selectedDate=d),
            child:DecoratedBox(decoration:BoxDecoration(
              color:selected?Theme.of(context).colorScheme.primaryContainer:null,
              border:Border.all(color:isToday?Theme.of(context).colorScheme.primary:Colors.transparent),
              borderRadius:BorderRadius.circular(12)),
              child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
                Text('$day',style:TextStyle(fontWeight:selected||isToday?FontWeight.bold:FontWeight.normal)),
                if(items.isNotEmpty) Padding(padding:const EdgeInsets.only(top:4),
                  child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[
                    for(final item in items.take(3)) Padding(padding:const EdgeInsets.symmetric(horizontal:1),
                      child:CircleAvatar(radius:3,backgroundColor:categoryColor(ctrl.categoryOf(item.event.categoryId)))),
                  ])),
              ])),
          );
        }),
    ])));
  }
  Widget _weekList(AppController ctrl,DateTime start,DateTime end) {
    final occurrences=ctrl.between(start,end);
    return Card(child:Padding(padding:const EdgeInsets.all(8),
      child:SingleChildScrollView(scrollDirection:Axis.horizontal,
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[const SizedBox(width:54),
            for(var i=0;i<7;i++) SizedBox(width:135,child:Center(
              child:Text(DateFormat('EEE dd.MM','uk').format(start.add(Duration(days:i))),
                style:const TextStyle(fontWeight:FontWeight.bold))))]),
          for(var hour=0;hour<24;hour++) Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
            SizedBox(width:54,height:68,child:Padding(padding:const EdgeInsets.only(top:6),
              child:Text('${hour.toString().padLeft(2,'0')}:00'))),
            for(var i=0;i<7;i++) Builder(builder:(ctx){
              final day=start.add(Duration(days:i));
              final hourItems=occurrences.where((x)=>sameDay(x.start,day) && x.start.hour==hour).toList();
              return SizedBox(width:135,child:InkWell(
                onTap:hourItems.isEmpty ? ()=>_newEvent(DateTime(day.year,day.month,day.day,hour)) : null,
                child:Container(constraints:const BoxConstraints(minHeight:68),padding:const EdgeInsets.all(3),
                  decoration:BoxDecoration(border:Border.all(
                    color:Theme.of(context).dividerColor.withValues(alpha:.35))),
                  child:Column(children:[for(final x in hourItems)
                    InkWell(onTap:()=>_openDetails(x),child:Container(
                      width:double.infinity,margin:const EdgeInsets.only(bottom:3),
                      padding:const EdgeInsets.all(5),decoration:BoxDecoration(
                        color:categoryColor(ctrl.categoryOf(x.event.categoryId)).withValues(alpha:.19),
                        borderRadius:BorderRadius.circular(5)),
                      child:Text('${timeText(x.start)} ${x.title}',maxLines:2,
                        overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11))))])),
              ));
            }),
          ]),
        ]))));
  }
  Widget _dayList(AppController ctrl,DateTime date) {
    final items=ctrl.between(dayStart(date),dayEnd(date));
    return Card(child:Padding(padding:const EdgeInsets.all(10),child:Column(children:[
      for(var hour=0;hour<24;hour++) InkWell(
        onTap:()=>_newEvent(DateTime(date.year,date.month,date.day,hour)),
        child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
          SizedBox(width:64,child:Padding(padding:const EdgeInsets.only(top:12),
            child:Text('${hour.toString().padLeft(2,'0')}:00'))),
          Expanded(child:Container(constraints:const BoxConstraints(minHeight:56),
            decoration:BoxDecoration(border:Border(bottom:BorderSide(
              color:Theme.of(context).dividerColor.withValues(alpha:.4)))),
            child:Column(children:[for(final occ in items.where((x)=>x.start.hour==hour))
              EventTile(occurrence:occ,category:ctrl.categoryOf(occ.event.categoryId),
                onTap:()=>_openDetails(occ))]))),
        ])),
    ])));
  }
  Widget _dayItems(AppController ctrl,DateTime date) {
    final occurrences=ctrl.between(dayStart(date),dayEnd(date));
    if(occurrences.isEmpty) return const Padding(padding:EdgeInsets.all(20),
      child:Text('У цей день подій немає. Натисни «Додати подію», щоб запланувати справу.'));
    return Column(children:[for(final occ in occurrences) EventTile(
      occurrence:occ,category:ctrl.categoryOf(occ.event.categoryId),
      onTap:()=>_openDetails(occ))]);
  }


  Widget _search(AppController ctrl) => SearchPane(controller:ctrl,
    onOpen:_openDetails);
  Widget _categories(AppController ctrl) => CategoryPane(controller:ctrl);
  Widget _settings(AppController ctrl) => SettingsPane(controller:ctrl);
}

class SearchPane extends StatefulWidget {
  final AppController controller;
  final ValueChanged<EventOccurrence> onOpen;
  const SearchPane({super.key,required this.controller,required this.onOpen});
  @override State<SearchPane> createState()=>_SearchPaneState();
}
class _SearchPaneState extends State<SearchPane> {
  String query='';int? category;DateTimeRange? range;
  @override Widget build(BuildContext context) {
    final now=DateTime.now();
    final from=range?.start ?? DateTime(now.year-2);
    final to=range==null ? DateTime(now.year+8) : dayEnd(range!.end);
    final q=query.toLowerCase();
    final matches=widget.controller.between(from,to).where((occ){
      final e=occ.event;
      return (category==null || e.categoryId==category) &&
        (q.isEmpty || occ.title.toLowerCase().contains(q) ||
          e.description.toLowerCase().contains(q) || e.location.toLowerCase().contains(q));
    }).take(250).toList();
    return ListView(padding:const EdgeInsets.all(18),children:[
      Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:900),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Пошук подій',style:Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height:14),
          TextField(onChanged:(v)=>setState(()=>query=v),
            decoration:const InputDecoration(prefixIcon:Icon(Icons.search),
              hintText:'Пошук за назвою, описом або місцем')),
          const SizedBox(height:12),
          Wrap(spacing:12,runSpacing:8,crossAxisAlignment:WrapCrossAlignment.center,children:[
            DropdownButton<int?>(value:category,hint:const Text('Категорія'),
              items:[const DropdownMenuItem<int?>(value:null,child:Text('Усі категорії')),
                for(final c in widget.controller.categories)
                  DropdownMenuItem<int?>(value:c.id,child:Text(c.name))],
              onChanged:(v)=>setState(()=>category=v)),
            OutlinedButton.icon(icon:const Icon(Icons.date_range_outlined),
              label:Text(range==null?'Фільтр дат':'${dateText(range!.start)} — ${dateText(range!.end)}'),
              onPressed:() async {final r=await showDateRangePicker(context:context,
                firstDate:DateTime(2000),lastDate:DateTime(2100),initialDateRange:range);
                if(r!=null) setState(()=>range=r);}),
            if(range!=null) TextButton(onPressed:()=>setState(()=>range=null),child:const Text('Очистити дати')),
          ]),
          Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text('Знайдено: ${matches.length}${matches.length==250?' (показано перші 250)':''}')),
          if(matches.isEmpty) const EmptyState(icon:Icons.search_off,
            title:'Подій не знайдено',subtitle:'Спробуй інший запит або зміни фільтри.'),
          for(final occ in matches) EventTile(occurrence:occ,
            category:widget.controller.categoryOf(occ.event.categoryId),
            onTap:()=>widget.onOpen(occ)),
        ]))),
    ]);
  }
}

class CategoryPane extends StatelessWidget {
  final AppController controller;
  const CategoryPane({super.key,required this.controller});
  static const palette=['#2878C8','#DB8745','#7956B3','#31967B',
    '#DC5174','#F59E0B','#64748B','#16A1BA'];
  Future<void> _edit(BuildContext context,[Category? existing]) async {
    final text=TextEditingController(text:existing?.name ?? '');
    var hex=existing?.colorHex ?? palette.first;
    final result=await showDialog<({String name,String hex})>(context:context,builder:(ctx)=>
      StatefulBuilder(builder:(ctx,setState)=>AlertDialog(
        title:Text(existing==null?'Нова категорія':'Редагувати категорію'),
        content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
          TextField(controller:text,maxLength:60,decoration:const InputDecoration(labelText:'Назва категорії')),
          const SizedBox(height:8),const Text('Колір'),
          Wrap(spacing:7,children:[for(final color in palette)
            IconButton(tooltip:color,onPressed:()=>setState(()=>hex=color),
              icon:Icon(hex==color?Icons.check_circle:Icons.circle,
                color:Color(int.parse('FF${color.substring(1)}',radix:16))))]),
        ]),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Скасувати')),
          FilledButton(onPressed:()=>text.text.trim().isEmpty?null:Navigator.pop(ctx,
            (name:text.text.trim(),hex:hex)),child:const Text('Зберегти'))],
      )));
    text.dispose();
    if(result==null || !context.mounted) return;
    try {
      if(existing==null) await controller.addCategory(result.name,result.hex);
      else await controller.editCategory(Category(existing.id,result.name,result.hex));
    } catch(e){if(context.mounted) showFailure(context,e);}
  }
  Future<void> _delete(BuildContext context,Category category) async {
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Видалення категорії'),
      content:Text('Видалити «${category.name}»? Події залишаться без категорії.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Скасувати')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Видалити'))]));
    if(ok==true && context.mounted) {
      try {await controller.removeCategory(category.id);}catch(e){if(context.mounted)showFailure(context,e);}
    }
  }
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(18),children:[
    Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:800),child:Column(
      crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[Expanded(child:Text('Категорії',style:Theme.of(context).textTheme.headlineMedium)),
        FilledButton.icon(onPressed:()=>_edit(context),icon:const Icon(Icons.add),label:const Text('Створити'))]),
      const SizedBox(height:6),const Text('Колір категорії відображається в календарі.'),
      const SizedBox(height:16),
      for(final c in controller.categories) Card(child:ListTile(
        leading:CircleAvatar(backgroundColor:categoryColor(c)),title:Text(c.name),
        subtitle:Text('${controller.events.where((e)=>e.categoryId==c.id).length} серій / подій'),
        trailing:Wrap(spacing:0,children:[
          IconButton(tooltip:'Редагувати',onPressed:()=>_edit(context,c),icon:const Icon(Icons.edit_outlined)),
          IconButton(tooltip:'Видалити',onPressed:()=>_delete(context,c),icon:const Icon(Icons.delete_outline)),
        ]))),
    ]))),
  ]);
}

class SettingsPane extends StatelessWidget {
  final AppController controller;
  const SettingsPane({super.key,required this.controller});
  Future<void> _export(BuildContext context) async {
    try {
      final json=await controller.repository.exportJson();
      final location=await BackupService().exportFile(json);
      if(context.mounted)showMessage(context,location==null?'Збереження скасовано':'Резервну копію збережено');
    } catch(e) {if(context.mounted)showFailure(context,e);}
  }
  Future<void> _import(BuildContext context) async {
    try {
      final json=await BackupService().importFile();
      if(json==null || !context.mounted) return;
      final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
        title:const Text('Відновлення з копії'),
        content:const Text('Ця дія замінить УСІ поточні події, категорії та налаштування. '
          'Перед продовженням радимо створити резервну копію.'),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Скасувати')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Замінити дані'))]));
      if(ok!=true || !context.mounted) return;
      await controller.importJson(json);
      if(context.mounted)showMessage(context,'Базу даних успішно відновлено');
    } catch(e){if(context.mounted)showFailure(context,e);}
  }
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(18),children:[
    Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:800),child:Column(
      crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('Налаштування',style:Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height:14),
      Text('Оформлення',style:Theme.of(context).textTheme.titleLarge),
      const SizedBox(height:8),
      Card(child:Column(children:[for(final opt in [
        (key:'system',title:'Як у системі',icon:Icons.brightness_auto),
        (key:'light',title:'Світла тема',icon:Icons.light_mode),
        (key:'dark',title:'Темна тема',icon:Icons.dark_mode),
      ]) RadioListTile<String>(title:Text(opt.title),secondary:Icon(opt.icon),
        value:opt.key,groupValue:controller.theme,
        onChanged:(v) async {if(v!=null) {
          try {await controller.setTheme(v);}catch(e){if(context.mounted)showFailure(context,e);}
        }} )])),
      const SizedBox(height:18),
      Text('Дані й резервні копії',style:Theme.of(context).textTheme.titleLarge),
      const SizedBox(height:8),
      Card(child:Column(children:[
        ListTile(leading:const Icon(Icons.save_alt),title:const Text('Експорт у JSON'),
          subtitle:Text(controller.repository is ApiEventRepository
            ? 'Експорт доступний лише для локальної SQLite' : 'Зберегти всі дані у файл'),
          onTap:controller.repository is ApiEventRepository?null:()=>_export(context)),
        const Divider(height:1),
        ListTile(leading:const Icon(Icons.restore),title:const Text('Імпорт із JSON'),
          subtitle:Text(controller.repository is ApiEventRepository
            ? 'Імпорт доступний лише для локальної SQLite' : 'Замінити дані резервною копією'),
          onTap:controller.repository is ApiEventRepository?null:()=>_import(context)),
      ])),
      const SizedBox(height:18),
      Card(child:ListTile(leading:const Icon(Icons.notifications_outlined),
        title:const Text('Локальні сповіщення'),
        subtitle:Text(controller.notifications.supported
          ? (controller.notificationWarning ?? 'Доступні на Android / iOS. Нагадування плануються на найближчі 90 днів.')
          : 'На Windows працюють усі функції даних. Системні сповіщення реалізовані для Android / iOS.'),
        trailing:controller.notifications.supported?TextButton(
          onPressed:() async {final granted=await controller.notifications.requestPermission();
            if(context.mounted)showMessage(context,granted?'Дозвіл надано':'Дозвіл не надано');},
          child:const Text('Дозвіл')):null)),
      const SizedBox(height:14),
      Text(controller.repository is ApiEventRepository
        ? 'Версія 1.1 • Flutter + FastAPI • Дані на сервері (SQLite).'
        : 'Версія 1.1 • Flutter + SQLite • Дані зберігаються тільки на пристрої.',
        style:Theme.of(context).textTheme.bodySmall),
    ]))),
  ]);
}
