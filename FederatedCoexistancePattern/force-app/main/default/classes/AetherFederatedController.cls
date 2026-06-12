public with sharing class AetherFederatedController {
    private static final String ERP_NAMED_CREDENTIAL = 'callout:Aether_ERP';
    private static final String BILLING_NAMED_CREDENTIAL = 'callout:Aether_Billing';

    @AuraEnabled(cacheable=true)
    public static FederatedResponse getFederatedData(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('An Account Id is required.');
        }

        Account acc = [
            SELECT Id,
                   Name,
                   Global_UUID__c,
                   Account_Tier__c,
                   Owner.Name,
                   Phone,
                   Website,
                   LastActivityDate
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];

        if (String.isBlank(acc.Global_UUID__c)) {
            throw new AuraHandledException('Global UUID is missing on the Account.');
        }

        Decimal openPipeline = getOpenPipeline(accountId);
        Integer openCases = [
            SELECT COUNT()
            FROM Case
            WHERE AccountId = :accountId AND IsClosed = false
        ];

        Map<String, Object> erpData = performCallout(
            ERP_NAMED_CREDENTIAL + '/erp/customer/' + EncodingUtil.urlEncode(acc.Global_UUID__c, 'UTF-8')
        );
        Map<String, Object> billingData = performCallout(
            BILLING_NAMED_CREDENTIAL + '/finance/customer/' + EncodingUtil.urlEncode(acc.Global_UUID__c, 'UTF-8')
        );

        FederatedResponse response = new FederatedResponse();
        response.accountId = acc.Id;
        response.accountName = acc.Name;
        response.globalUuid = acc.Global_UUID__c;
        response.crm = buildCrmContext(acc, openPipeline, openCases);
        response.erp = buildErpContext(erpData);
        response.billing = buildBillingContext(billingData);
        response.healthScore = calculateHealthScore(response.crm, response.erp, response.billing);
        response.warnings = collectWarnings(response.erp, response.billing);
        return response;
    }

    @TestVisible
    private static Map<String, Object> performCallout(String endpoint) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod('GET');
        request.setHeader('Accept', 'application/json');

        HttpResponse response = new Http().send(request);
        Integer statusCode = response.getStatusCode();

        if (statusCode < 200 || statusCode >= 300) {
            throw new AuraHandledException('Callout failed for endpoint ' + endpoint + ' with status ' + statusCode + '.');
        }

        Object raw = JSON.deserializeUntyped(response.getBody());
        if (!(raw instanceof Map<String, Object>)) {
            throw new AuraHandledException('Unexpected payload received from ' + endpoint + '.');
        }

        return (Map<String, Object>) raw;
    }

    private static Decimal getOpenPipeline(Id accountId) {
        AggregateResult[] results = [
            SELECT SUM(Amount) totalAmount
            FROM Opportunity
            WHERE AccountId = :accountId
              AND IsClosed = false
        ];

        if (results.isEmpty() || results[0].get('totalAmount') == null) {
            return 0;
        }

        return (Decimal) results[0].get('totalAmount');
    }

    private static CRMContext buildCrmContext(Account acc, Decimal openPipeline, Integer openCases) {
        CRMContext crm = new CRMContext();
        crm.ownerName = acc.Owner != null ? acc.Owner.Name : null;
        crm.tier = acc.Account_Tier__c;
        crm.openPipeline = openPipeline;
        crm.lastActivityDate = acc.LastActivityDate;
        crm.openCases = openCases;
        crm.phone = acc.Phone;
        crm.website = acc.Website;
        return crm;
    }

    private static ERPContext buildErpContext(Map<String, Object> data) {
        ERPContext erp = new ERPContext();
        erp.productionStatus = stringValue(data, 'production_status');
        erp.chipType = stringValue(data, 'chip_type');
        erp.currentProductionBatch = firstStringValue(data, new List<String>{
            'current_production_batch',
            'active_batch',
            'batch_number'
        });
        erp.qualityControlStatus = firstStringValue(data, new List<String>{
            'quality_control_status',
            'qc_status'
        });
        erp.shippingEta = firstStringValue(data, new List<String>{
            'shipping_eta',
            'eta'
        });
        erp.warehouseLocation = firstStringValue(data, new List<String>{
            'warehouse_location',
            'warehouse'
        });
        return erp;
    }

    private static BillingContext buildBillingContext(Map<String, Object> data) {
        BillingContext billing = new BillingContext();
        billing.creditLimit = decimalValue(data, 'credit_limit');
        billing.balanceDue = decimalValue(data, 'balance_due');
        billing.dso = integerValue(data, 'dso');
        billing.paymentHistory = firstStringValue(data, new List<String>{
            'payment_history',
            'payment_profile'
        });
        return billing;
    }

    private static String calculateHealthScore(CRMContext crm, ERPContext erp, BillingContext billing) {
        Integer score = 50;

        if (crm.openPipeline != null && crm.openPipeline > 1000000) {
            score += 20;
        }

        if (billing.balanceDue != null && billing.balanceDue > 0 && billing.creditLimit != null) {
            Decimal utilization = billing.balanceDue / billing.creditLimit;
            if (utilization < 0.25) {
                score += 10;
            } else if (utilization > 0.75) {
                score -= 20;
            }
        }

        if (billing.dso != null) {
            if (billing.dso <= 30) {
                score += 10;
            } else if (billing.dso >= 60) {
                score -= 20;
            }
        }

        if (erp.productionStatus != null && erp.productionStatus.toLowerCase().contains('halt')) {
            score -= 25;
        } else if (erp.productionStatus != null && erp.productionStatus.toLowerCase().contains('assembl')) {
            score += 5;
        }

        score = Math.max(0, Math.min(100, score));

        if (score >= 80) {
            return 'Strong';
        }
        if (score >= 60) {
            return 'Watch';
        }
        return 'At Risk';
    }

    private static List<String> collectWarnings(ERPContext erp, BillingContext billing) {
        List<String> warnings = new List<String>();

        if (erp.productionStatus != null && erp.productionStatus.toLowerCase().contains('halt')) {
            warnings.add('ERP indicates a production halt that may impact fulfillment.');
        }

        if (billing.dso != null && billing.dso >= 60) {
            warnings.add('Billing indicates overdue behavior with elevated DSO.');
        }

        if (billing.balanceDue != null && billing.creditLimit != null && billing.balanceDue > billing.creditLimit) {
            warnings.add('Balance due exceeds the assigned credit limit.');
        }

        return warnings;
    }

    private static String stringValue(Map<String, Object> data, String key) {
        Object value = data.get(key);
        return value == null ? null : String.valueOf(value);
    }

    private static String firstStringValue(Map<String, Object> data, List<String> keys) {
        for (String key : keys) {
            String value = stringValue(data, key);
            if (!String.isBlank(value)) {
                return value;
            }
        }
        return null;
    }

    private static Decimal decimalValue(Map<String, Object> data, String key) {
        Object value = data.get(key);
        if (value == null) {
            return null;
        }
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        return Decimal.valueOf(String.valueOf(value));
    }

    private static Integer integerValue(Map<String, Object> data, String key) {
        Object value = data.get(key);
        if (value == null) {
            return null;
        }
        if (value instanceof Integer) {
            return (Integer) value;
        }
        return Integer.valueOf(String.valueOf(value));
    }

    public class FederatedResponse {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String globalUuid;
        @AuraEnabled public CRMContext crm;
        @AuraEnabled public ERPContext erp;
        @AuraEnabled public BillingContext billing;
        @AuraEnabled public String healthScore;
        @AuraEnabled public List<String> warnings;
    }

    public class CRMContext {
        @AuraEnabled public String ownerName;
        @AuraEnabled public String tier;
        @AuraEnabled public Decimal openPipeline;
        @AuraEnabled public Date lastActivityDate;
        @AuraEnabled public Integer openCases;
        @AuraEnabled public String phone;
        @AuraEnabled public String website;
    }

    public class ERPContext {
        @AuraEnabled public String productionStatus;
        @AuraEnabled public String chipType;
        @AuraEnabled public String currentProductionBatch;
        @AuraEnabled public String qualityControlStatus;
        @AuraEnabled public String shippingEta;
        @AuraEnabled public String warehouseLocation;
    }

    public class BillingContext {
        @AuraEnabled public Decimal creditLimit;
        @AuraEnabled public Decimal balanceDue;
        @AuraEnabled public Integer dso;
        @AuraEnabled public String paymentHistory;
    }
}
