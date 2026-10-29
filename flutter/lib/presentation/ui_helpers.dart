import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../domain/models.dart';

String dayText(DateTime day) => DateFormat('d MMMM yyyy','uk').format(day);
String dateText(DateTime date) => DateFormat('dd.MM.yyyy','uk').format(date);
String timeText(DateTime date) => DateFormat('HH:mm','uk').format(date);
String dateTimeText(DateTime date) => '${dateText(date)} о ${timeText(date)}';
String statusText(String status) => switch(status) {
  'DONE'=>'Виконано','MISSED'=>'Пропущено',_=>'Заплановано',
};
Color categoryColor(Category? category) {
  final value=category?.colorHex.replaceFirst('#','') ?? '64748B';
  return Color(int.parse('FF$value',radix:16));
}

Future<void> showFailure(BuildContext context,Object error) async {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content:Text('Помилка: $error'),behavior:SnackBarBehavior.floating,
  ));
}
void showMessage(BuildContext context,String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content:Text(text),behavior:SnackBarBehavior.floating,
  ));
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const EmptyState({super.key,required this.icon,required this.title,required this.subtitle});
  @override
  Widget build(BuildContext context) => Center(child:Padding(
    padding:const EdgeInsets.all(32),
    child:Column(mainAxisSize:MainAxisSize.min,children:[
      Icon(icon,size:52,color:Theme.of(context).colorScheme.primary.withValues(alpha:.5)),
      const SizedBox(height:16),Text(title,style:Theme.of(context).textTheme.titleLarge),
      const SizedBox(height:8),Text(subtitle,textAlign:TextAlign.center,
        style:Theme.of(context).textTheme.bodyMedium),
    ]),
  ));
}

class EventTile extends StatelessWidget {
  final EventOccurrence occurrence;
  final Category? category;
  final VoidCallback onTap;
  const EventTile({super.key,required this.occurrence,required this.category,required this.onTap});
  @override
  Widget build(BuildContext context) {
    final color=categoryColor(category);
    final completed=occurrence.status!='PLANNED';
    return Card(margin:const EdgeInsets.symmetric(vertical:5),clipBehavior:Clip.antiAlias,
      child:InkWell(onTap:onTap,child:Padding(padding:const EdgeInsets.all(14),
        child:Row(children:[
          Container(width:4,height:56,decoration:BoxDecoration(color:color,borderRadius:BorderRadius.circular(6))),
          const SizedBox(width:14),
          SizedBox(width:52,child:Column(children:[
            Text(timeText(occurrence.start),style:const TextStyle(fontWeight:FontWeight.bold,fontSize:14)),
            if(occurrence.end!=null) Text(timeText(occurrence.end!),style:Theme.of(context).textTheme.labelSmall),
          ])),
          const SizedBox(width:12),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(occurrence.title,maxLines:2,overflow:TextOverflow.ellipsis,
              style:TextStyle(fontWeight:FontWeight.w700,fontSize:15,
                decoration:completed ? TextDecoration.lineThrough : null)),
            const SizedBox(height:4),
            Text([if(category!=null)category!.name,
              if(occurrence.event.location.isNotEmpty)occurrence.event.location,
              if(completed)statusText(occurrence.status)].join(' · '),
              maxLines:1,overflow:TextOverflow.ellipsis,
              style:Theme.of(context).textTheme.bodySmall),
          ])),
          if(occurrence.event.recurrence!=null)
            const Padding(padding:EdgeInsets.only(right:8),child:Icon(Icons.repeat,size:18)),
          const Icon(Icons.chevron_right),
        ]),
      )));
  }
}
