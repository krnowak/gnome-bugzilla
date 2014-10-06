function showOrHideGnomeAttachmentStatus() {
    var combo = document.getElementById('attachment_gnome_attachment_status_combo');
    var hidden = document.getElementById('attachment_gnome_attachment_status_hidden');
    var ispatch = document.getElementById('ispatch');

    if (combo !== null && hidden !== null){
	if (ispatch.checked) {
            YAHOO.util.Dom.replaceClass(combo, 'gnome_attachment_status_is_not_a_patch', 'gnome_attachment_status_is_a_patch');
            YAHOO.util.Dom.replaceClass(hidden, 'gnome_attachment_status_is_a_patch', 'gnome_attachment_status_is_not_a_patch');
	} else {
            YAHOO.util.Dom.replaceClass(combo, 'gnome_attachment_status_is_a_patch', 'gnome_attachment_status_is_not_a_patch');
            YAHOO.util.Dom.replaceClass(hidden, 'gnome_attachment_status_is_not_a_patch', 'gnome_attachment_status_is_a_patch');
	}
    }

    1;
}

document.addEventListener('DOMContentLoaded', function () {
    ispatch = document.getElementById('ispatch');
    if (ispatch !== null) {
	ispatch.addEventListener('change', showOrHideGnomeAttachmentStatus);
    }
});
