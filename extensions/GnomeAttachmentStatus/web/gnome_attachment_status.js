function show_hide_gnome_attachment_status(evt) {
    var combo = document.getElementById('attachment_gnome_attachment_status');

    if (document.getElementById('ispatch').checked){
        YAHOO.util.Dom.replaceClass(combo, 'gnome_attachment_status_is_not_a_patch', 'gnome_attachment_status_is_a_patch');
    }else{
        YAHOO.util.Dom.replaceClass(combo, 'gnome_attachment_status_is_a_patch', 'gnome_attachment_status_is_not_a_patch');
    }

    1;
}

document.addEventListener('DOMContentLoaded', function () {
    document.getElementById('ispatch').addEventListener('input', show_hide_gnome_attachment_status);
});
