// Developer snapshot helper. Logs can contain visible case data; keep raw output private.
for(String view : new List<String>{'MY','TEAM'}) {
 CaseRiskAnalyzer.Request req=new CaseRiskAnalyzer.Request();req.view=view;req.demoOnly=true;
 System.debug('CASEPULSE_'+view+'='+JSON.serialize(CaseRiskAnalyzer.analyze(new List<CaseRiskAnalyzer.Request>{req})[0].console));
}
