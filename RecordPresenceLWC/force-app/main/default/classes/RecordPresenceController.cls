public with sharing class RecordPresenceController {
    private static final Set<String> SUPPORTED_ACTIONS = new Set<String>{ 'Viewing', 'Present', 'Left' };

    @AuraEnabled
    public static void publishEvent(String recordId, String objectApiName, String action) {
        if (
            String.isBlank(recordId) ||
            String.isBlank(objectApiName) ||
            String.isBlank(action) ||
            !SUPPORTED_ACTIONS.contains(action)
        ) {
            return;
        }

        User currentUser = [
            SELECT Id, Name
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        List<Database.SaveResult> results = EventBus.publish(new List<RecordPresenceEvent__e>{
            buildEvent(recordId, objectApiName, action, currentUser)
        });

        for (Database.SaveResult sr : results) {
            if (!sr.isSuccess()) {
                for (Database.Error err : sr.getErrors()) {
                    System.debug(
                        'Error publishing record presence event: ' +
                            err.getStatusCode() +
                            ' - ' +
                            err.getMessage()
                    );
                }
            }
        }
    }

    @TestVisible
    private static RecordPresenceEvent__e buildEvent(
        String recordId,
        String objectApiName,
        String action,
        User currentUser
    ) {
        return new RecordPresenceEvent__e(
            RecordId__c = recordId,
            ObjectApiName__c = objectApiName,
            UserId__c = currentUser.Id,
            UserName__c = currentUser.Name,
            UserAction__c = action
        );
    }
}