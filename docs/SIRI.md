# Siri grocery capture

The iOS 27+ app includes the Add Grocery Item action in Shortcuts. In the app, open Settings → Add with Siri to choose a device-local default from editable lists. A shortcut can select a different list explicitly. When there are several eligible lists and no default, the action asks for the destination.

## Personal Shortcut

1. Open Shortcuts and create a new shortcut with **Dictate Text**. Set the dictation language as needed.
2. Add **Add Grocery Item** from the Groceries app. Pass the dictated text into **Item**. Optionally select **List**, or use the default set in the app.
3. Give the shortcut a distinctive name. Run it from Shortcuts first, then try asking Siri to run the shortcut by name.

Try dictating `שלוש חבילות פסטה` into the Item field. Recognized quantities and units are optional. Leave the automation request identifier blank unless the caller generates and reuses a UUID for retries of the same request.

Apple lists Hebrew (Israel) for Siri and on-device offline requests. App Shortcut phrases include the app name token. These capabilities do not establish that a particular Hebrew phrase will route to this action. The personal shortcut and exact utterances still need testing on an iPhone.

## Device release checks

- With the app terminated, run the action from Shortcuts and check that a single new item persists after relaunch. Repeat with Hebrew and English Siri, using both a default and an explicitly selected list. Record the OS version, Siri language and exact phrases, including the desired phrase without the app name.
- Test Siri while locked. The action requires local device authentication. Confirm the system asks to unlock before it accesses the list.
- Test Dictate Text in airplane mode and test a Shortcuts action with a fixed Item value separately. The second test isolates app persistence from system dictation. After reconnecting, verify the item on a second account, the widget and the paired Watch.
- With a read-only participant and a stale shortcut to a deleted list, verify that the action refuses the write. After a share permission change, allow one online sync to refresh the device's cached permission.
- Try a learned aisle, a known product with a matching aisle, and an unknown product. With optional product recognition connected, verify that a later recognized alias can refine an unassigned row and leaves an explicitly moved row in place.
- Run two deliberate adds separately and verify the quantity increases. Retry a shortcut action with the same request UUID and verify the second execution leaves the quantity alone. Siri requests without a UUID use a two-second replay window for identical inputs. Explicit UUIDs are retained on the originating device for one day.
