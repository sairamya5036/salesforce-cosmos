public with sharing class CaseRescueApply {
  public class Request {
    @InvocableVariable(required=true)
    public Id caseId;
    @InvocableVariable(required=true)
    public Boolean approved;
  }
  public class Response {
    @InvocableVariable
    public String message;
  }
  @InvocableMethod(
    label='Apply Approved Case Rescue'
    description='Internal Screen Flow action. Do not expose as an MCP tool.'
  )
  public static List<Response> apply(List<Request> requests) {
    Set<Id> ids = new Set<Id>();
    for (Request req : requests) {
      if (req.approved != true)
        throw new CasePulseAccess.AccessException(
          'Explicit approval is required.'
        );
      if (req.caseId == null || req.caseId.getSObjectType() != Case.SObjectType)
        throw new CasePulseAccess.AccessException(
          'A valid Case ID is required.'
        );
      ids.add(req.caseId);
    }
    // Lock the parent before testing the marker, serializing concurrent rescues.
    Map<Id, Case> records = new Map<Id, Case>(
      [
        SELECT Id, OwnerId, IsClosed, IsEscalated, CasePulse_Rescue_Task__c
        FROM Case
        WHERE Id IN :ids
        WITH USER_MODE
        FOR UPDATE
      ]
    );
    Set<Id> authorizedOwners = CasePulseAccess.rescueOwners();
    List<Case> updates = new List<Case>();
    List<Task> tasks = new List<Task>();
    List<Id> taskCases = new List<Id>();
    Set<Id> seen = new Set<Id>();
    for (Request req : requests) {
      Case record = records.get(req.caseId);
      if (record == null)
        throw new CasePulseAccess.AccessException('Case unavailable.');
      CasePulseAccess.requireCase(record, authorizedOwners);
      if (seen.contains(record.Id))
        continue;
      seen.add(record.Id);
      updates.add(new Case(Id = record.Id, IsEscalated = true));
      if (String.isBlank(record.CasePulse_Rescue_Task__c)) {
        tasks.add(
          new Task(
            WhatId = record.Id,
            OwnerId = UserInfo.getUserId(),
            Subject = 'CasePulse: SLA rescue follow-up',
            Status = 'Not Started',
            Priority = 'High',
            ActivityDate = Date.today(),
            Description = 'Explicitly approved in CasePulse. Review the SLA risk, contact the customer, and document the next step.'
          )
        );
        taskCases.add(record.Id);
      }
    }
    Savepoint sp = Database.setSavepoint();
    try {
      insert as user tasks;
      update as user updates;
      // Only this trusted action writes the private idempotency marker.
      List<Case> markers = new List<Case>();
      for (Integer i = 0; i < tasks.size(); i++)
        markers.add(
          new Case(Id = taskCases[i], CasePulse_Rescue_Task__c = tasks[i].Id)
        );
      update markers;
    } catch (Exception e) {
      Database.rollback(sp);
      throw e;
    }
    List<Response> results = new List<Response>();
    for (Request req : requests) {
      Response r = new Response();
      r.message = 'Rescue recorded. Escalation is flagged and the existing or newly created follow-up Task is available on the case.';
      results.add(r);
    }
    return results;
  }
}
