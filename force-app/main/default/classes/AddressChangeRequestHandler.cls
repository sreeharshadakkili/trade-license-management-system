/**
 * Class: AddressChangeRequestHandler
 *
 * Purpose: Business logic for address change request processing.
 * Handles automatic License address updates after payment confirmation.
 *
 * Key Responsibilities:
 * - Detect payment confirmation (Payment_Confirmed__c changed to TRUE)
 * - Update parent License address fields
 * - Use Custom Setting bypass to circumvent validation rules
 * - Mark requests as Completed
 * - Set card reprint flags
 * - Handle bulk operations (200+ records)
 * - Prevent recursion
 *
 * Design Patterns:
 * - Trigger Handler Pattern (separates trigger from business logic)
 * - Bulkification (collections, no SOQL in loops)
 * - Recursion Prevention (static boolean flag)
 * - Custom Setting Bypass Pattern
 *
 * Change History:
 * - 2026-04-07: Initial version (Take-home assignment)
 * - 2026-04-09: Increment Address_Change_Count__c on each confirmed change;
 *               reset Card_Reprint_Required__c to false when a new request
 *               is submitted so it only reflects the pending reprint.
 */
public class AddressChangeRequestHandler {

    /**
     * Recursion prevention flag.
     * Prevents infinite trigger loops if updates cause re-triggers.
     */
    private static Boolean isProcessing = false;

    /**
     * Main handler method for payment confirmation events.
     * Called from AddressChangeRequestTrigger (after update context).
     *
     * @param newRequests - Trigger.new (list of updated Address_Change_Request__c records)
     * @param oldMap - Trigger.oldMap (map of old versions of records, keyed by Id)
     *
     * Business Logic:
     * 1. Check recursion flag - exit if already processing
     * 2. Loop through updated requests
     * 3. Detect payment confirmation (Payment_Confirmed__c changed from FALSE to TRUE)
     * 4. Collect License records that need address updates
     * 5. Enable Custom Setting bypass
     * 6. Bulk update License records
     * 7. Disable Custom Setting bypass
     * 8. Mark requests as Completed
     *
     * Bulkification:
     * - Uses lists/maps to collect records (no SOQL/DML in loops)
     * - Single SOQL to fetch current License counts before building updates
     * - Single DML for Licenses, single DML for Requests
     */
    public static void handlePaymentConfirmation(
        List<Address_Change_Request__c> newRequests,
        Map<Id, Address_Change_Request__c> oldMap
    ) {
        // Recursion check - exit if already processing
        if (isProcessing) {
            return;
        }

        // Set flag to prevent recursion
        isProcessing = true;

        try {
            // --- Pass 1: identify which License IDs need updating ---
            Set<Id> licenseIdsToProcess = new Set<Id>();
            for (Address_Change_Request__c newRequest : newRequests) {
                Address_Change_Request__c oldRequest = oldMap.get(newRequest.Id);
                Boolean paymentJustConfirmed =
                    newRequest.Payment_Confirmed__c == true &&
                    oldRequest.Payment_Confirmed__c == false &&
                    newRequest.Status__c == 'Payment Confirmed';
                if (paymentJustConfirmed) {
                    licenseIdsToProcess.add(newRequest.License__c);
                }
            }

            if (licenseIdsToProcess.isEmpty()) {
                return;
            }

            // Single SOQL outside the loop — fetch current counts for all affected Licenses
            Map<Id, License__c> licenseMap = new Map<Id, License__c>([
                SELECT Id, Address_Change_Count__c
                FROM License__c
                WHERE Id IN :licenseIdsToProcess
            ]);

            // --- Pass 2: build update records using current counts ---
            List<License__c> licensesToUpdate = new List<License__c>();
            List<Address_Change_Request__c> requestsToComplete = new List<Address_Change_Request__c>();

            for (Address_Change_Request__c newRequest : newRequests) {
                Address_Change_Request__c oldRequest = oldMap.get(newRequest.Id);
                Boolean paymentJustConfirmed =
                    newRequest.Payment_Confirmed__c == true &&
                    oldRequest.Payment_Confirmed__c == false &&
                    newRequest.Status__c == 'Payment Confirmed';

                if (paymentJustConfirmed) {
                    License__c currentLicense = licenseMap.get(newRequest.License__c);
                    Decimal currentCount = (currentLicense.Address_Change_Count__c == null)
                        ? 0
                        : currentLicense.Address_Change_Count__c;

                    License__c licenseToUpdate = new License__c(
                        Id = newRequest.License__c,
                        Business_Street__c          = newRequest.New_Street__c,
                        Business_City__c            = newRequest.New_City__c,
                        Business_State__c           = newRequest.New_State__c,
                        Business_Postal_Code__c     = newRequest.New_Postal_Code__c,
                        Last_Address_Change_Date__c = System.now(),
                        Card_Reprint_Required__c    = true,
                        Address_Change_Count__c     = currentCount + 1
                    );
                    licensesToUpdate.add(licenseToUpdate);

                    // Stage the request completion (separate DML after License update)
                    requestsToComplete.add(new Address_Change_Request__c(
                        Id = newRequest.Id,
                        Status__c = 'Completed',
                        Payment_Confirmation_Date__c = System.now()
                    ));
                }
            }

            // --- Enable bypass so validation rule allows address changes ---
            Bypass_Validation__c bypass = Bypass_Validation__c.getOrgDefaults();
            if (bypass == null) {
                bypass = new Bypass_Validation__c();
            }
            bypass.Allow_Address_Change__c = true;
            upsert bypass;

            try {
                // Single bulk DML for all License updates
                update licensesToUpdate;
            } finally {
                // Always disable bypass — even if the License update fails
                bypass.Allow_Address_Change__c = false;
                upsert bypass;
            }

            // Mark requests as Completed AFTER License update succeeds
            // Separate DML avoids Master-Detail row-locking conflicts
            update requestsToComplete;

        } catch (DmlException e) {
            System.debug(LoggingLevel.ERROR, 'DML Error in handlePaymentConfirmation: ' + e.getMessage());
            throw new AddressChangeException('Failed to update License address: ' + e.getDmlMessage(0));

        } finally {
            // Always reset recursion flag, even if an exception is thrown
            isProcessing = false;
        }
    }

    /**
     * Custom exception class for address change errors.
     * Provides meaningful error messages surfaced to the caller.
     */
    public class AddressChangeException extends Exception {}
}
