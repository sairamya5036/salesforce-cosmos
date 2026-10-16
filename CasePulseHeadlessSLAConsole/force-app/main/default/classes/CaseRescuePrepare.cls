global with sharing class CaseRescuePrepare {
  global class Request {
    @InvocableVariable(required=true)
    global Id caseId;
  }
  global class Response {
    @InvocableVariable
    global String confirmationUrl;
    @InvocableVariable
    global String caseLabel;
    @InvocableVariable
    global String proposedChanges;
  }
  @InvocableMethod(
    label='Prepare Case Rescue'
    description='Read-only: validate an open case and return its Salesforce approval link. Never escalates a case.'
  )
  global static List<Response> prepare(List<Request> requests) {
    Set<Id> ids = new Set<Id>();
    for (Request req : requests) {
      if (req.caseId == null || req.caseId.getSObjectType() != Case.SObjectType)
        throw new CasePulseAccess.AccessException(
          'A valid Case ID is required.'
        );
      ids.add(req.caseId);
    }
    Map<Id, Case> records = new Map<Id, Case>(
      [
        SELECT Id, CaseNumber, Subject, OwnerId, IsClosed
        FROM Case
        WHERE Id IN :ids
        WITH USER_MODE
      ]
    );
    Set<Id> authorizedOwners = CasePulseAccess.rescueOwners();
    List<Response> results = new List<Response>();
    for (Request req : requests) {
      Case record = records.get(req.caseId);
      if (record == null)
        throw new CasePulseAccess.AccessException('Case unavailable.');
      CasePulseAccess.requireCase(record, authorizedOwners);
      Response result = new Response();
      result.caseLabel = record.CaseNumber + ' — ' + record.Subject;
      result.confirmationUrl =
        URL.getOrgDomainUrl().toExternalForm() +
        '/flow/CasePulse_Confirm_Rescue?caseId=' +
        record.Id;
      result.proposedChanges = 'Set Escalated and create one follow-up Task assigned to you, due today. No change until you approve in Salesforce.';
      results.add(result);
    }
    return results;
  }
}
