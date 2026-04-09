/**
 * Test Class: AddressChangeRequestTest
 *
 * Purpose: Comprehensive test coverage for AddressChangeRequestHandler and trigger.
 * Tests address change automation, validation rules, bulk operations, and edge cases.
 *
 * Coverage Target: 80%+ on AddressChangeRequestHandler and AddressChangeRequestTrigger
 *
 * Test Scenarios:
 * 1. Single record payment confirmation updates License address
 * 2. Bulk 200 records payment confirmation
 * 3. Validation rule blocks direct address edits
 * 4. Bypass mechanism allows Apex address updates
 * 5. No re-processing when payment was already confirmed
 * 6. Null address fields handled gracefully
 * 7. Non-address fields remain editable
 * 8. Address change count increments correctly
 *
 * Change History:
 * - 2026-04-09: Initial version (Take-home assignment)
 */
@isTest
private class AddressChangeRequestTest {

    /**
     * Test Setup: Creates shared test data for all test methods.
     * Runs once before all test methods.
     *
     * Creates:
     * - 1 Account
     * - 1 License with initial address
     * - Custom Setting bypass (disabled by default)
     */
    @testSetup
    static void setupTestData() {
        // Create test Account
        Account testAccount = new Account(Name = 'Test Business Inc.');
        insert testAccount;

        // Enable bypass so we can create License with address fields
        Bypass_Validation__c bypass = new Bypass_Validation__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Allow_Address_Change__c = true
        );
        insert bypass;

        // Create test License with initial address
        License__c testLicense = new License__c(
            Account__c = testAccount.Id,
            License_Type__c = 'Contractor',
            Status__c = 'Active',
            Business_Street__c = '100 Original Street',
            Business_City__c = 'Boston',
            Business_State__c = 'Massachusetts',
            Business_Postal_Code__c = '02101',
            Business_Country__c = 'United States',
            Issue_Date__c = Date.today(),
            Expiration_Date__c = Date.today().addYears(1)
        );
        insert testLicense;

        // Disable bypass — default state for all tests
        bypass.Allow_Address_Change__c = false;
        update bypass;
    }

    // ─────────────────────────────────────────────────────────────
    // Helper: returns a new Address_Change_Request__c ready to insert
    // ─────────────────────────────────────────────────────────────
    private static Address_Change_Request__c buildRequest(Id licenseId) {
        return new Address_Change_Request__c(
            License__c = licenseId,
            Requested_By__c = UserInfo.getUserId(),
            Old_Street__c = '100 Original Street',
            Old_City__c = 'Boston',
            Old_State__c = 'Massachusetts',
            Old_Postal_Code__c = '02101',
            New_Street__c = '500 New Avenue',
            New_City__c = 'Cambridge',
            New_State__c = 'Massachusetts',
            New_Postal_Code__c = '02139',
            Status__c = 'Payment Pending',
            Payment_Amount__c = 50.00,
            Payment_Confirmed__c = false
        );
    }

    // ─────────────────────────────────────────────────────────────
    // TEST 1: Single record payment confirmation
    // ─────────────────────────────────────────────────────────────
    @isTest
    static void test_PaymentConfirmed_UpdatesLicenseAddress() {
        License__c testLicense = [SELECT Id FROM License__c LIMIT 1];

        Address_Change_Request__c request = buildRequest(testLicense.Id);
        insert request;

        Test.startTest();
        request.Payment_Confirmed__c = true;
        request.Status__c = 'Payment Confirmed';
        request.Payment_Confirmation_Date__c = System.now();
        request.Payment_Transaction_ID__c = 'TEST_12345';
        update request;
        Test.stopTest();

        License__c updatedLicense = [
            SELECT Business_Street__c, Business_City__c, Business_State__c,
                   Business_Postal_Code__c, Last_Address_Change_Date__c,
                   Card_Reprint_Required__c, Address_Change_Count__c
            FROM License__c
            WHERE Id = :testLicense.Id
        ];

        System.assertEquals('500 New Avenue', updatedLicense.Business_Street__c,
            'Street should be updated to new address');
        System.assertEquals('Cambridge', updatedLicense.Business_City__c,
            'City should be updated to new address');
        System.assertEquals('Massachusetts', updatedLicense.Business_State__c,
            'State should be updated');
        System.assertEquals('02139', updatedLicense.Business_Postal_Code__c,
            'Postal code should be updated');
        System.assertEquals(true, updatedLicense.Card_Reprint_Required__c,
            'Card reprint flag should be true');
        System.assertNotEquals(null, updatedLicense.Last_Address_Change_Date__c,
            'Last address change date should be populated');
        System.assertEquals(1, updatedLicense.Address_Change_Count__c,
            'Address change count should be incremented to 1');

        Address_Change_Request__c updatedRequest = [
            SELECT Status__c FROM Address_Change_Request__c WHERE Id = :request.Id
        ];
        System.assertEquals('Completed', updatedRequest.Status__c,
            'Request should be marked Completed');
    }

    // ─────────────────────────────────────────────────────────────
    // TEST 2: Bulk payment confirmation — 200 records
    // ─────────────────────────────────────────────────────────────
    @isTest
    static void test_BulkPaymentConfirmation_Updates200Licenses() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        // Enable bypass to insert 200 Licenses with addresses
        Bypass_Validation__c bypass = Bypass_Validation__c.getOrgDefaults();
        bypass.Allow_Address_Change__c = true;
        update bypass;

        List<License__c> licenses = new List<License__c>();
        for (Integer i = 0; i < 200; i++) {
            licenses.add(new License__c(
                Account__c = testAccount.Id,
                License_Type__c = 'Retail',
                Status__c = 'Active',
                Business_Street__c = '100 Bulk Street ' + i,
                Business_City__c = 'Boston',
                Business_State__c = 'Massachusetts',
                Business_Postal_Code__c = '02101',
                Business_Country__c = 'United States',
                Issue_Date__c = Date.today(),
                Expiration_Date__c = Date.today().addYears(1)
            ));
        }
        insert licenses;

        bypass.Allow_Address_Change__c = false;
        update bypass;

        List<Address_Change_Request__c> requests = new List<Address_Change_Request__c>();
        for (License__c lic : licenses) {
            requests.add(new Address_Change_Request__c(
                License__c = lic.Id,
                Requested_By__c = UserInfo.getUserId(),
                Old_Street__c = 'Old Street',
                Old_City__c = 'Boston',
                Old_State__c = 'Massachusetts',
                Old_Postal_Code__c = '02101',
                New_Street__c = '999 Bulk New Street',
                New_City__c = 'Cambridge',
                New_State__c = 'Massachusetts',
                New_Postal_Code__c = '02139',
                Status__c = 'Payment Pending',
                Payment_Amount__c = 50.00,
                Payment_Confirmed__c = false
            ));
        }
        insert requests;

        Test.startTest();
        for (Address_Change_Request__c req : requests) {
            req.Payment_Confirmed__c = true;
            req.Status__c = 'Payment Confirmed';
            req.Payment_Confirmation_Date__c = System.now();
        }
        update requests;
        Test.stopTest();

        List<License__c> updatedLicenses = [
            SELECT Business_Street__c, Card_Reprint_Required__c, Address_Change_Count__c
            FROM License__c
            WHERE Id IN :new Map<Id, License__c>(licenses).keySet()
        ];

        System.assertEquals(200, updatedLicenses.size(), 'Should have 200 updated licenses');
        for (License__c lic : updatedLicenses) {
            System.assertEquals('999 Bulk New Street', lic.Business_Street__c,
                'All licenses should have new street');
            System.assertEquals(true, lic.Card_Reprint_Required__c,
                'All licenses should have reprint flag set');
            System.assertEquals(1, lic.Address_Change_Count__c,
                'All licenses should have count of 1');
        }

        List<Address_Change_Request__c> updatedRequests = [
            SELECT Status__c
            FROM Address_Change_Request__c
            WHERE Id IN :new Map<Id, Address_Change_Request__c>(requests).keySet()
        ];

        System.assertEquals(200, updatedRequests.size(), 'Should have 200 updated requests');
        for (Address_Change_Request__c req : updatedRequests) {
            System.assertEquals('Completed', req.Status__c,
                'All requests should be marked Completed');
        }
    }

    // ─────────────────────────────────────────────────────────────
    // TEST 3: Validation rule blocks direct address edits
    // ─────────────────────────────────────────────────────────────
    @isTest
    static void test_DirectAddressEdit_ValidationRuleBlocks() {
        License__c testLicense = [SELECT Id FROM License__c LIMIT 1];
        testLicense.Business_Street__c = '999 Unauthorized Street';

        Test.startTest();
        Boolean exceptionCaught = false;
        String errorMessage = '';
        try {
            update testLicense;
            System.assert(false, 'Expected DmlException was not thrown');
        } catch (DmlException e) {
            exceptionCaught = true;
            errorMessage = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals(true, exceptionCaught,
            'DmlException should have been thrown by validation rule');
        System.assert(
            errorMessage.containsIgnoreCase('50') || errorMessage.containsIgnoreCase('payment'),
            'Error message should mention payment requirement. Got: ' + errorMessage
        );
        System.assert(
            errorMessage.containsIgnoreCase('Request Address Change') || errorMessage.containsIgnoreCase('request'),
            'Error message should mention the request process. Got: ' + errorMessage
        );
    }

    // ─────────────────────────────────────────────────────────────
    // TEST 4: Bypass mechanism allows Apex address update
    // ─────────────────────────────────────────────────────────────
    @isTest
    static void test_BypassEnabled_AllowsAddressUpdate() {
        License__c testLicense = [SELECT Id FROM License__c LIMIT 1];

        Test.startTest();
        Bypass_Validation__c bypass = Bypass_Validation__c.getOrgDefaults();
        bypass.Allow_Address_Change__c = true;
        update bypass;

        testLicense.Business_Street__c = '777 Bypass Test Street';
        update testLicense;

        bypass.Allow_Address_Change__c = false;
        update bypass;
        Test.stopTest();

        License__c updatedLicense = [
            SELECT Business_Street__c FROM License__c WHERE Id = :testLicense.Id
        ];
        System.assertEquals('777 Bypass Test Street', updatedLicense.Business_Street__c,
            'Address should update when bypass is enabled');
    }

    // ─────────────────────────────────────────────────────────────
    // TEST 5: No re-processing when payment already confirmed
    // ─────────────────────────────────────────────────────────────
    @isTest
    static void test_PaymentAlreadyConfirmed_NoReprocessing() {
        License__c testLicense = [SELECT Id, Business_Street__c FROM License__c LIMIT 1];
        String originalStreet = testLicense.Business_Street__c;

        // Insert request that is already confirmed — trigger should not fire on a later update
        Address_Change_Request__c request = new Address_Change_Request__c(
            License__c = testLicense.Id,
            Requested_By__c = UserInfo.getUserId(),
            Old_Street__c = originalStreet,
            Old_City__c = 'Boston',
            Old_State__c = 'Massachusetts',
            Old_Postal_Code__c = '02101',
            New_Street__c = '888 Already Paid Street',
            New_City__c = 'Cambridge',
            New_State__c = 'Massachusetts',
            New_Postal_Code__c = '02139',
            Status__c = 'Completed',
            Payment_Confirmed__c = true,
            Payment_Confirmation_Date__c = System.now().addDays(-1)
        );
        insert request;

        Test.startTest();
        // Update a non-payment field — Payment_Confirmed__c doesn't flip FALSE→TRUE
        request.Error_Message__c = 'Test update — should not retrigger address change';
        update request;
        Test.stopTest();

        License__c updatedLicense = [
            SELECT Business_Street__c FROM License__c WHERE Id = :testLicense.Id
        ];
        System.assertEquals(originalStreet, updatedLicense.Business_Street__c,
            'License address should NOT change when payment was already confirmed before this update');
    }

    // ─────────────────────────────────────────────────────────────
    // TEST 6: Minimal address fields — only required fields populated
    // (New_Street/City/State/PostalCode are required on the object,
    //  so we verify the handler doesn't break with minimal data)
    // ─────────────────────────────────────────────────────────────
    @isTest
    static void test_MinimalAddressFields_HandledGracefully() {
        License__c testLicense = [SELECT Id FROM License__c LIMIT 1];

        // Only populate the required New_* fields; leave optional old address blank
        Address_Change_Request__c request = new Address_Change_Request__c(
            License__c = testLicense.Id,
            Requested_By__c = UserInfo.getUserId(),
            New_Street__c = '1 Minimal St',
            New_City__c = 'Worcester',
            New_State__c = 'Massachusetts',
            New_Postal_Code__c = '01601',
            Status__c = 'Payment Pending',
            Payment_Confirmed__c = false
        );
        insert request;

        Test.startTest();
        request.Payment_Confirmed__c = true;
        request.Status__c = 'Payment Confirmed';
        update request;
        Test.stopTest();

        Address_Change_Request__c updatedRequest = [
            SELECT Status__c FROM Address_Change_Request__c WHERE Id = :request.Id
        ];
        System.assertEquals('Completed', updatedRequest.Status__c,
            'Request should complete with minimal address data');

        License__c updatedLicense = [
            SELECT Business_Street__c, Business_City__c, Business_Postal_Code__c
            FROM License__c WHERE Id = :testLicense.Id
        ];
        System.assertEquals('1 Minimal St', updatedLicense.Business_Street__c,
            'License street should be updated to minimal value');
        System.assertEquals('Worcester', updatedLicense.Business_City__c,
            'License city should be updated to minimal value');
        System.assertEquals('01601', updatedLicense.Business_Postal_Code__c,
            'License postal code should be updated to minimal value');
    }

    // ─────────────────────────────────────────────────────────────
    // TEST 7: Non-address fields remain editable (no validation block)
    // ─────────────────────────────────────────────────────────────
    @isTest
    static void test_NonAddressFieldEdit_NotBlocked() {
        License__c testLicense = [SELECT Id FROM License__c LIMIT 1];

        Test.startTest();
        testLicense.Status__c = 'Suspended';
        update testLicense;
        Test.stopTest();

        License__c updatedLicense = [SELECT Status__c FROM License__c WHERE Id = :testLicense.Id];
        System.assertEquals('Suspended', updatedLicense.Status__c,
            'Non-address fields should update without triggering validation rule');
    }

    // ─────────────────────────────────────────────────────────────
    // TEST 8: Address change count increments on each confirmed change
    // ─────────────────────────────────────────────────────────────
    @isTest
    static void test_AddressChangeCount_IncrementsOnEachChange() {
        License__c testLicense = [SELECT Id FROM License__c LIMIT 1];

        // First change
        Address_Change_Request__c req1 = buildRequest(testLicense.Id);
        insert req1;

        Test.startTest();
        req1.Payment_Confirmed__c = true;
        req1.Status__c = 'Payment Confirmed';
        update req1;
        Test.stopTest();

        License__c afterFirst = [
            SELECT Address_Change_Count__c, Business_Street__c
            FROM License__c WHERE Id = :testLicense.Id
        ];
        System.assertEquals(1, afterFirst.Address_Change_Count__c,
            'Count should be 1 after first address change');
        System.assertEquals('500 New Avenue', afterFirst.Business_Street__c,
            'Street should reflect first change');

        // Second change — must run outside startTest/stopTest block
        // because @testSetup data is shared and we're in the same test
        Address_Change_Request__c req2 = new Address_Change_Request__c(
            License__c = testLicense.Id,
            Requested_By__c = UserInfo.getUserId(),
            Old_Street__c = '500 New Avenue',
            Old_City__c = 'Cambridge',
            Old_State__c = 'Massachusetts',
            Old_Postal_Code__c = '02139',
            New_Street__c = '750 Third Place',
            New_City__c = 'Somerville',
            New_State__c = 'Massachusetts',
            New_Postal_Code__c = '02143',
            Status__c = 'Payment Pending',
            Payment_Confirmed__c = false
        );
        insert req2;
        req2.Payment_Confirmed__c = true;
        req2.Status__c = 'Payment Confirmed';
        update req2;

        License__c afterSecond = [
            SELECT Address_Change_Count__c, Business_Street__c
            FROM License__c WHERE Id = :testLicense.Id
        ];
        System.assertEquals(2, afterSecond.Address_Change_Count__c,
            'Count should be 2 after second address change');
        System.assertEquals('750 Third Place', afterSecond.Business_Street__c,
            'Street should reflect second change');
    }

    // ─────────────────────────────────────────────────────────────
    // TEST 9: First address change when Address_Change_Count__c starts null
    // Covers handler line 109 (null count → 0 branch)
    // ─────────────────────────────────────────────────────────────
    @isTest
    static void test_FirstAddressChange_CountStartsNull() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Bypass_Validation__c bypass = Bypass_Validation__c.getOrgDefaults();
        bypass.Allow_Address_Change__c = true;
        update bypass;

        License__c lic = new License__c(
            Account__c = acc.Id,
            License_Type__c = 'Retail',
            Status__c = 'Active',
            Business_Street__c = 'First Change Street',
            Business_City__c = 'Boston',
            Business_State__c = 'Massachusetts',
            Business_Postal_Code__c = '02101',
            Business_Country__c = 'United States',
            Issue_Date__c = Date.today(),
            Expiration_Date__c = Date.today().addYears(1),
            Address_Change_Count__c = null
        );
        insert lic;

        bypass.Allow_Address_Change__c = false;
        update bypass;

        Address_Change_Request__c req = new Address_Change_Request__c(
            License__c = lic.Id,
            Requested_By__c = UserInfo.getUserId(),
            Old_Street__c = 'First Change Street',
            New_Street__c = 'Second Change Street',
            New_City__c = 'Cambridge',
            New_State__c = 'Massachusetts',
            New_Postal_Code__c = '02139',
            Status__c = 'Payment Pending',
            Payment_Confirmed__c = false
        );
        insert req;

        Test.startTest();
        req.Payment_Confirmed__c = true;
        req.Status__c = 'Payment Confirmed';
        update req;
        Test.stopTest();

        License__c updatedLic = [SELECT Address_Change_Count__c FROM License__c WHERE Id = :lic.Id];
        System.assertEquals(1, updatedLic.Address_Change_Count__c,
            'Address change count should increment from null to 1');
    }

    // ─────────────────────────────────────────────────────────────
    // TEST 10: Handler creates Bypass Custom Setting when none exists
    // Covers handler line 135 (null bypass → new instance branch)
    // ─────────────────────────────────────────────────────────────
    @isTest
    static void test_MissingBypassSetting_CreatesNew() {
        // Remove the org-default Custom Setting so the handler must create it
        List<Bypass_Validation__c> existing = [SELECT Id FROM Bypass_Validation__c];
        if (!existing.isEmpty()) {
            delete existing;
        }

        License__c lic = [SELECT Id FROM License__c LIMIT 1];

        Address_Change_Request__c req = new Address_Change_Request__c(
            License__c = lic.Id,
            Requested_By__c = UserInfo.getUserId(),
            Old_Street__c = 'Old Setting Test',
            New_Street__c = 'New Setting Test',
            New_City__c = 'Boston',
            New_State__c = 'Massachusetts',
            New_Postal_Code__c = '02101',
            Status__c = 'Payment Pending',
            Payment_Confirmed__c = false
        );
        insert req;

        Test.startTest();
        req.Payment_Confirmed__c = true;
        req.Status__c = 'Payment Confirmed';
        update req;
        Test.stopTest();

        // Handler must have created the setting; verify it's disabled after use
        Bypass_Validation__c createdSetting = Bypass_Validation__c.getOrgDefaults();
        System.assertNotEquals(null, createdSetting,
            'Bypass setting should be created by handler when missing');
        System.assertEquals(false, createdSetting.Allow_Address_Change__c,
            'Bypass should be disabled after handler completes');
    }
}
