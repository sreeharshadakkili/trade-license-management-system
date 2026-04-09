/**
 * Trigger: AddressChangeRequestTrigger
 * Object: Address_Change_Request__c
 *
 * Purpose: Automatically updates parent License address fields when payment is confirmed.
 *
 * Context: after update
 *
 * Business Logic:
 * - Detects when Payment_Confirmed__c changes from FALSE to TRUE
 * - Updates parent License__c address fields with new address from request
 * - Sets Card_Reprint_Required__c flag to trigger card printing workflow
 * - Marks request as "Completed"
 *
 * Change History:
 * - 2026-04-07: Initial version (Take-home assignment)
 */
trigger AddressChangeRequestTrigger on Address_Change_Request__c (after update) {
    // Delegate all logic to handler class (best practice: keep triggers thin)
    if (Trigger.isAfter && Trigger.isUpdate) {
        AddressChangeRequestHandler.handlePaymentConfirmation(Trigger.new, Trigger.oldMap);
    }
}
