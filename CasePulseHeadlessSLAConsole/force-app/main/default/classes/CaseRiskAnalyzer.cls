global with sharing class CaseRiskAnalyzer {
  global class Request {
    @InvocableVariable(
      label='View'
      description='MY or TEAM. Omit for the permission-derived default.'
    )
    global String view;
    @InvocableVariable(
      label='Demo cases only'
      description='Optional: only fictional CasePulse demo records. Does not widen user scope.'
    )
    global Boolean demoOnly;
  }
  global class Response {
    @InvocableVariable
    global ConsoleData console;
  }
  global class ConsoleData {
    @AuraEnabled
    global String title;
    @AuraEnabled
    global String view;
    @AuraEnabled
    global String analyzedAt;
    @AuraEnabled
    global Integer totalCount;
    @AuraEnabled
    global Integer evaluatedCount;
    @AuraEnabled
    global Integer criticalCount = 0;
    @AuraEnabled
    global Integer highCount = 0;
    @AuraEnabled
    global Integer watchCount = 0;
    @AuraEnabled
    global Integer healthyCount = 0;
    @AuraEnabled
    global Boolean truncated;
    @AuraEnabled
    global Boolean empty;
    @AuraEnabled
    global String summary;
    @AuraEnabled
    global String notice;
    @AuraEnabled
    global String refreshPrompt;
    @AuraEnabled
    global List<RiskCase> cases = new List<RiskCase>();
  }
  global class RiskCase implements Comparable {
    @AuraEnabled
    global String caseId;
    @AuraEnabled
    global String caseNumber;
    @AuraEnabled
    global String subject;
    @AuraEnabled
    global String owner;
    @AuraEnabled
    global String priority;
    @AuraEnabled
    global String deadlineSource;
    @AuraEnabled
    global String deadlineLabel;
    @AuraEnabled
    global Datetime deadline;
    @AuraEnabled
    global String lastResponseAt;
    @AuraEnabled
    global Integer score = 0;
    @AuraEnabled
    global String severity;
    @AuraEnabled
    global String color;
    @AuraEnabled
    global String reasons;
    @AuraEnabled
    global String recordUrl;
    @AuraEnabled
    global String rescuePrompt;
    @AuraEnabled
    global Boolean escalated;
    global Integer compareTo(Object other) {
      RiskCase r = (RiskCase) other;
      if (score != r.score)
        return score > r.score ? -1 : 1;
      if (deadline != r.deadline) {
        if (deadline == null)
          return 1;
        if (r.deadline == null)
          return -1;
        return deadline < r.deadline ? -1 : 1;
      }
      return caseNumber.compareTo(r.caseNumber);
    }
  }
  @InvocableMethod(
    label='Analyze Case Risk'
    description='Read-only deterministic SLA rescue analysis. MY for own cases; TEAM requires manager permission.'
  )
  global static List<Response> analyze(List<Request> requests) {
    if (requests == null || requests.isEmpty())
      return new List<Response>();
    // Reuse identical view/filter scans when Flow bulk-invokes this action.
    Map<String, ConsoleData> cache = new Map<String, ConsoleData>();
    List<Response> results = new List<Response>();
    for (Request req : requests) {
      String view = req == null || String.isBlank(req.view)
        ? (CasePulseAccess.isManager() ? 'TEAM' : 'MY')
        : req.view.toUpperCase();
      if (view != 'MY' && view != 'TEAM')
        throw new CasePulseAccess.AccessException('View must be MY or TEAM.');
      Boolean demoOnly = req != null && req.demoOnly == true;
      String cacheKey = view + ':' + demoOnly;
      if (!cache.containsKey(cacheKey))
        cache.put(cacheKey, scan(view, demoOnly));
      Response result = new Response();
      result.console = cache.get(cacheKey);
      results.add(result);
    }
    return results;
  }
  private static ConsoleData scan(String view, Boolean demoOnly) {
    Set<Id> owners = CasePulseAccess.ownerScope(view == 'TEAM');
    ConsoleData data = new ConsoleData();
    data.view = view;
    data.title = view == 'TEAM'
      ? 'Team SLA Command Center'
      : 'My SLA Rescue Queue';
    Datetime nowAt = System.now();
    data.analyzedAt = nowAt.formatGmt('yyyy-MM-dd HH:mm:ss') + ' UTC';
    String filter =
      ' WHERE IsClosed = false AND OwnerId IN :owners' +
      (demoOnly ? ' AND CasePulse_Demo__c = true' : '');
    data.totalCount = Database.countQuery(
      'SELECT COUNT() FROM Case' + filter + ' WITH USER_MODE'
    );
    List<Case> records = Database.query(
      'SELECT Id, CaseNumber, Subject, Priority, OwnerId, Owner.Name, CreatedDate, IsEscalated, CasePulse_Demo_Deadline__c, CasePulse_Reopen_Count__c FROM Case' +
        filter +
        ' WITH USER_MODE ORDER BY CreatedDate ASC, Id ASC LIMIT 500'
    );
    Set<Id> ids = new Map<Id, Case>(records).keySet();
    Map<Id, Datetime> deadlines = new Map<Id, Datetime>();
    // Optional feature detection. Permission errors fail closed instead of silently downgrading real SLAs.
    Schema.SObjectType milestoneType = Schema.getGlobalDescribe()
      .get('CaseMilestone');
    if (milestoneType != null) {
      for (
        SObject row : Database.query(
          'SELECT CaseId, MIN(TargetDate) deadline FROM CaseMilestone WHERE CaseId IN :ids AND IsCompleted = false WITH USER_MODE GROUP BY CaseId'
        )
      ) {
        deadlines.put((Id) row.get('CaseId'), (Datetime) row.get('deadline'));
      }
    }
    Map<Id, Datetime> responses = new Map<Id, Datetime>();
    for (AggregateResult row : [
      SELECT ParentId, MAX(MessageDate) latest
      FROM EmailMessage
      WHERE ParentId IN :ids AND Incoming = FALSE
      WITH USER_MODE
      GROUP BY ParentId
    ]) {
      responses.put((Id) row.get('ParentId'), (Datetime) row.get('latest'));
    }
    List<RiskCase> ranked = new List<RiskCase>();
    for (Case record : records) {
      Datetime deadline = deadlines.get(record.Id);
      String source = deadline != null
        ? 'CaseMilestone'
        : (record.CasePulse_Demo_Deadline__c != null
            ? 'Demo SLA'
            : 'SLA unavailable');
      if (deadline == null)
        deadline = record.CasePulse_Demo_Deadline__c;
      Datetime lastResponse = responses.get(record.Id);
      RiskCase risk = score(record, deadline, source, lastResponse, nowAt);
      ranked.add(risk);
      if (risk.severity == 'Critical')
        data.criticalCount++;
      else if (risk.severity == 'High')
        data.highCount++;
      else if (risk.severity == 'Watch')
        data.watchCount++;
      else
        data.healthyCount++;
    }
    ranked.sort();
    for (Integer i = 0; i < Math.min(20, ranked.size()); i++)
      data.cases.add(ranked[i]);
    data.evaluatedCount = records.size();
    data.empty = records.isEmpty();
    data.truncated = data.totalCount > data.cases.size();
    data.summary =
      data.criticalCount +
      ' Critical · ' +
      data.highCount +
      ' High · ' +
      data.watchCount +
      ' Watch · ' +
      data.healthyCount +
      ' Healthy';
    data.refreshPrompt =
      'Call analyzeCaseRisk with view ' +
      view +
      ' and demoOnly ' +
      demoOnly +
      '.';
    data.notice =
      (demoOnly ? 'Fictional demo cases only. ' : '') +
      'Showing ' +
      data.cases.size() +
      ' of ' +
      data.totalCount +
      ' open cases. Risk counts cover ' +
      records.size() +
      ' evaluated cases (oldest 500 maximum). Elapsed-time heuristics; demo deadlines are not contractual SLAs.';
    return data;
  }
  @TestVisible
  private static RiskCase score(
    Case record,
    Datetime deadline,
    String source,
    Datetime lastResponse,
    Datetime nowAt
  ) {
    RiskCase risk = new RiskCase();
    risk.caseId = record.Id;
    risk.caseNumber = record.CaseNumber;
    risk.subject = record.Subject;
    risk.owner = record.Owner == null
      ? String.valueOf(record.OwnerId)
      : record.Owner.Name;
    risk.priority = record.Priority;
    risk.deadline = deadline;
    risk.deadlineSource = source;
    risk.escalated = record.IsEscalated;
    List<String> reasons = new List<String>();
    if (deadline != null && deadline <= nowAt) {
      risk.score += 60;
      reasons.add('SLA deadline breached +60');
    } else if (deadline != null && deadline <= nowAt.addMinutes(60)) {
      risk.score += 40;
      reasons.add('SLA due within 60 minutes +40');
    }
    if (
      record.Priority == 'High' &&
      record.OwnerId.getSObjectType() == Group.SObjectType
    ) {
      risk.score += 25;
      reasons.add('High priority, queue owned +25');
    }
    Datetime responseBaseline = lastResponse == null
      ? record.CreatedDate
      : lastResponse;
    risk.lastResponseAt =
      responseBaseline.formatGmt('yyyy-MM-dd HH:mm:ss') +
      ' UTC' +
      (lastResponse == null
        ? ' (created; no outbound email)'
        : ' (outbound email)');
    if (responseBaseline <= nowAt.addHours(-8)) {
      risk.score += 20;
      reasons.add('No outbound email for 8 elapsed hours +20');
    }
    if (record.CasePulse_Reopen_Count__c >= 2) {
      risk.score += 15;
      reasons.add('Reopened at least twice +15');
    }
    risk.score = Math.min(100, risk.score);
    risk.severity = risk.score >= 60
      ? 'Critical'
      : (risk.score >= 30 ? 'High' : (risk.score > 0 ? 'Watch' : 'Healthy'));
    risk.color = risk.severity == 'Critical'
      ? 'error'
      : (risk.severity == 'Healthy' ? 'success' : 'warning');
    risk.reasons = reasons.isEmpty()
      ? 'No risk signals detected.'
      : String.join(reasons, ' · ');
    risk.deadlineLabel = deadline == null
      ? source
      : source + ' · ' + deadline.formatGmt('yyyy-MM-dd HH:mm') + ' UTC';
    risk.recordUrl = URL.getOrgDomainUrl().toExternalForm() + '/' + record.Id;
    risk.rescuePrompt =
      'Call prepareCaseRescue for caseId ' +
      record.Id +
      '. Return its approval link; do not claim the case is escalated until I approve in Salesforce.';
    return risk;
  }
}
