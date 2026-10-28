import 'dart:convert';
import 'dart:io';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_server/src/modules/builder/creation_pipeline_evaluation.dart';
import 'package:appnest_server/src/modules/builder/creation_pipeline_scenarios.dart';
import 'package:appnest_server/src/modules/builder/nemotron_scenarios.dart';
import 'package:appnest_server/src/modules/builder/nemotron_routes.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:crypto/crypto.dart';
void main(){
 final ids=['create-rich-dashboard','create-multistep-form','create-capacity-signup','create-transfer-reading','create-transfer-team','unsupported-executable'];
 final scenarios={for(final s in [...nemotronScenarios(),...creationPipelineTransferScenarios()])s.id:s};
 final rows=<Map<String,dynamic>>[];
 for(final id in ids){
  for(final profile in ['control','glm','scoped','plan','repair']){
   final model=profile=='glm'?pipelineFallbackModel:pipelineTargetModel;
   final provider={'scoped','plan','repair'}.contains(profile)
    ?ExperimentalCreationProvider(Uri.parse(nvidiaEvaluationBase),model,'synthetic-unused-key',pipeline:parseCreationPipeline(profile))
    :ChatCompletionProvider(Uri.parse(nvidiaEvaluationBase),model,'synthetic-unused-key',nvidiaModelEvaluation:true,nemotronProfile:NvidiaNemotronProfile.efficientCreation);
   final body=provider.adaptRequestForTransport(buildAiRequest(model,scenarios[id]!.prompt,starterTemplates()['reading']!,editing:false),generation:true);
   final encoded=jsonEncode(body);
   rows.add({'case':id,'profile':profile,'model':model,'bytes':utf8.encode(encoded).length,'sha256':sha256.convert(utf8.encode(encoded)).toString()});
  }
 }
 stdout.writeln(const JsonEncoder.withIndent('  ').convert({'networkCallsMade':false,'phase':'initial request only','requests':rows}));
}
