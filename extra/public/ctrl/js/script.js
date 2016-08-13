/**
 * Created by enukane on 2016/08/14.
 */

var _demo_ = false;

/* common utility */

function log_debug(msg) {
    console.info("[DEBUG] " + msg);
}

function log_warn(msg) {
    console.warn("[WARNING] " + msg);
}

function log_cmd(msg) {
    console.log("[CMD] " + msg);
}

function log_cmdresult(msg) {
    console.log("[CMD-RESULT] " + msg);
}

function log_periodic(msg) {
    console.log("[PERIODIC] " + msg);
}

function update_text(id, text) {
    $(id).text(text);
}

function update_status(json) {
    if (json == null) {
        return;
    }
    /*
     * json contains
     * [
     *  <macaddr>: {
     *      last_updated: <epoch>,
     *      wlan_assoc_count: <int>,
     *      wlan_disassoc_count: <int>,
     *      dhcp_event_count: <int>,
     *      dhcp_ack_count: <int>,
     *      dns_query_count: <int>,
     *      http_accessed_urls : [<url>],
     *      http_agents : [<agents>],
     *
     *  },
     *  ....
     * ]
     *
     */

    log_debug(json);
    macaddrs = Object.keys(json);
    log_debug("macaddrs => " + macaddrs);

    client_num = macaddrs.length;
    update_text("#dd-uniq-clients", client_num);
}

(function worker() {
    $.ajax({
        type: "get",
        url: '/api/v1/status',
        contentType: 'application/json',
        dataType: "json",
        success: function(json) {
            log_periodic("success > " + JSON.stringify(json));
            update_status(json);
        },
        error: function() {
            log_periodic("error");
        },
        complete: function() {
            log_periodic("schedule next");
            if (_demo_) {
                json = {
                    "00:11:22:33:44:55" : {
                        "test" : 0
                    },
                    "11:22:33:44:55:66" : {
                        "test" : 1
                    }
                }
                update_status(json);
            }
            setTimeout(worker, 500);
        }
    });
})();
