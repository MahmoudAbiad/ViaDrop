/// No audio samples, message content or session secrets are stored here.
class AudioDiagnostics {
 static const probe='VDPROBE1';
 int samples=0,elapsedMs=0,peak=0,nativePackets=0,packets=0,probes=0,starts=0,invalidStarts=0,route=-1;
 double rmsDbfs=-120,clippedPercent=0;
 bool recording=false;
 void metrics(Map<dynamic,dynamic> event){
  int number(String key)=>(event[key] as num?)?.toInt()??0;
  samples=number('samples');elapsedMs=number('elapsedMs');peak=number('peak');
  nativePackets=number('nativePackets');route=(event['inputRouteType'] as num?)?.toInt()??-1;
  rmsDbfs=(event['rmsDbfs'] as num?)?.toDouble()??-120;
  final count=number('windowSamples');clippedPercent=count>0?100*number('clipped')/count:0;
  recording=event['recording']==true;
 }
 String get routeName=>switch(route){15=>'ميكروفون الهاتف',7=>'Bluetooth SCO',3=>'سماعة سلكية',11||22=>'USB',-1=>'غير معلوم',_=>'نوع Android $route'};
 String get report=>[
  'تشخيص الصوت — قياسات رقمية وليست مستوى أمان للسمع',
  'التسجيل: ${recording?'نشط':'لم تصل قياساته بعد'} • المصدر: $routeName',
  'عينات: $samples • مدة: ${(elapsedMs/1000).toStringAsFixed(1)} s',
  'التقاط فعلي: ${elapsedMs>0?(samples*1000/elapsedMs).round():0} عينة/s (المطلوب 48000)',
  'RMS: ${rmsDbfs.toStringAsFixed(1)} dBFS • Peak: $peak • قص: ${clippedPercent.toStringAsFixed(1)}%',
  'GGWave في المحرك: $nativePackets • حزم وصلت للواجهة: $packets',
  'اختبار الرابط: $probes • بدايات صحيحة: $starts • بدايات غير صالحة: $invalidStarts',
  if(samples>0&&peak==0)'العينات الحالية صامتة رقمياً؛ لا يمكن تفسير ذلك كبداية نقل.',
  if(samples>0&&peak>0&&nativePackets==0)'الميكروفون يلتقط إشارة، لكن GGWave لم يفك حزمة بعد. هذا لا يثبت التقاط نغمة المرسل.',
 ].join('\n');
}
