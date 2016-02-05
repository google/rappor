// Dashboard UI functions.
//
// This is shared between all HTML pages.

'use strict';

// Append a message to an element.  Used for errors.
function appendMessage(elem, msg) {
  elem.innerHTML += msg + '<br />';
}

// jQuery-like AJAX helper, but simpler.

// Requires an element with id "status" to show errors.
//
// Args:
//   errElem: optional element to append error messages to.  If null, then
//     alert() on error.
//   success: callback that is passed the xhr object.
function ajaxGet(url, errElem, success) {
  var xhr = new XMLHttpRequest();
  xhr.open('GET', url, true /*async*/);
  xhr.onreadystatechange = function() {
    if (xhr.readyState != 4 /*DONE*/) {
      return;
    }

    if (xhr.status != 200) {
      var msg = 'ERROR requesting ' + url + ': ' + xhr.status + ' ' +
                xhr.statusText;
      if (errElem) {
        appendMessage(errElem, msg);
      } else {
        alert(msg);
      }
      return;
    }

    success(xhr);
  };
  xhr.send();
}

// Load metadata about the metrics.
// metric-metadata.json is just 14 KB, so we load it for every page.
//
// callback:
//   on metric page, just pick out the right description.
//   on overview page, populate them ALL with tool tips?
//   Or create another column?
function loadMetricMetadata(errElem, success) {
  // TODO: Should we make metric-metadata.json optional?  Some may not have it.

  ajaxGet('metric-metadata.json', errElem, function(xhr) {
    // TODO: handle parse error
    var m = JSON.parse(xhr.responseText);
    success(m);
  });
}

// for overview.html.
function initOverview(urlHash, tableStates, statusElem) {

  ajaxGet('cooked/overview.part.html', statusElem, function(xhr) {
    var elem = document.getElementById('overview');
    elem.innerHTML = xhr.responseText;
    makeTablesSortable(urlHash, [elem], tableStates);
    updateTables(urlHash, tableStates, statusElem);
  });

  loadMetricMetadata(statusElem, function(metadata) {
    var elem = document.getElementById('metricMetadata').tBodies[0];
    var metrics = metadata.metrics;

    // Sort by the metric name
    var metricNames = Object.getOwnPropertyNames(metrics);
    metricNames.sort();

    var tableHtml = '';
    for (var i = 0; i < metricNames.length; ++i) {
      var name = metricNames[i];
      var meta = metrics[name];
      tableHtml += '<tr>';
      tableHtml += '<td>' + name + '</td>';
      tableHtml += '<td>' + meta.owners + '</td>';
      tableHtml += '<td>' + meta.summary + '</td>';
      tableHtml += '</tr>';
    }
    elem.innerHTML += tableHtml;
  });
}

// for metric.html.
function initMetric(urlHash, tableStates, statusElem, globals) {

  var metricName = urlHash.get('metric');
  if (metricName === undefined) {
    appendMessage(statusElem, "Missing metric name in URL hash.");
    return;
  }

  loadMetricMetadata(statusElem, function(metadata) {
    var meta = metadata.metrics[metricName];
    if (!meta) {
      appendMessage(statusElem, 'Found no metadata for ' + metricName);
      return;
    }
    var descElem = document.getElementById('metricDesc');
    descElem.innerHTML = meta.summary;

    // TODO: put owners at the bottom of the page somewhere?
  });

  // Add title and page element
  document.title = metricName;
  var nameElem = document.getElementById('metricName');
  nameElem.innerHTML = metricName;

  // Add correct links.
  var u = document.getElementById('underlying-status');
  u.href = 'cooked/' + metricName + '/status.csv';

  var distUrl = 'cooked/' + metricName + '/dist.csv';
  var u2 = document.getElementById('underlying-dist');
  u2.href = distUrl;

  ajaxGet(distUrl, statusElem, function(xhr) {
    var csvData = xhr.responseText;
    var elem = document.getElementById('proportionsDy');
    // Mutate global so we can respond to onclick.
    globals.proportionsDygraph = new Dygraph(elem, csvData, {customBars: true});
  });

  var numReportsUrl = 'cooked/' + metricName + '/num_reports.csv';
  ajaxGet(numReportsUrl, statusElem, function(xhr) {
    var csvData = xhr.responseText;
    var elem = document.getElementById('num-reports-dy');
    var g = new Dygraph(elem, csvData);
  });

  var massUrl = 'cooked/' + metricName + '/mass.csv';
  ajaxGet(massUrl, statusElem, function(xhr) {
    var csvData = xhr.responseText;
    var elem = document.getElementById('mass-dy');
    var g = new Dygraph(elem, csvData);
  });

  var tableUrl = 'cooked/' + metricName + '/status.part.html';
  ajaxGet(tableUrl, statusElem, function(xhr) {
    var htmlData = xhr.responseText;
    var elem = document.getElementById('status_table');
    elem.innerHTML = htmlData;

    makeTablesSortable(urlHash, [elem], tableStates);
    updateTables(urlHash, tableStates, statusElem);
  });
}

// NOTE: This was for optional Dygraphs error bars, but it's not hooked up yet.
function onMetricCheckboxClick(checkboxElem, proportionsDygraph) {
  var checked = checkboxElem.checked;
  if (proportionsDygraph === null) {
    console.log('NULL');
  }
  proportionsDygraph.updateOptions({customBars: checked});
  console.log('HANDLED');
}

// for day.html.
function initDay(urlHash, tableStates, statusElem) {
  var jobId = urlHash.get('jobId');
  var metricName = urlHash.get('metric');
  var date = urlHash.get('date');

  var err = '';
  if (!jobId) {
    err = 'jobId missing from hash';
  }
  if (!metricName) {
    err = 'metric missing from hash';
  }
  if (!date) {
    err = 'date missing from hash';
  }
  if (err) {
    appendMessage(statusElem, err);
  }

  // Add title and page element
  var titleStr = metricName + ' on ' + date;
  document.title = titleStr;
  var mElem = document.getElementById('metricDay');
  mElem.innerHTML = titleStr;

  // Add correct links.
  var u = document.getElementById('underlying');
  u.href = '../' + jobId + '/raw/' + metricName + '/' + date +
           '/results.csv';

  // Add correct links.
  var u_res = document.getElementById('residual');
  u_res.src = '../' + jobId + '/raw/' + metricName + '/' + date +
              '/residual.png';

  var url = '../' + jobId + '/cooked/' + metricName + '/' + date + '.part.html';
  ajaxGet(url, statusElem, function(xhr) {
    var htmlData = xhr.responseText;
    var elem = document.getElementById('results_table');
    elem.innerHTML = htmlData;
    makeTablesSortable(urlHash, [elem], tableStates);
    updateTables(urlHash, tableStates, statusElem);
  });
}

// for assoc-overview.html.
function initAssocOverview(urlHash, tableStates, statusElem) {
  ajaxGet('cooked/assoc-overview.part.html', statusElem, function(xhr) {
    var elem = document.getElementById('overview');
    elem.innerHTML = xhr.responseText;
    makeTablesSortable(urlHash, [elem], tableStates);
    updateTables(urlHash, tableStates, statusElem);
  });
}

// for assoc-metric.html.
function initAssocMetric(urlHash, tableStates, statusElem) {
  var metricName = urlHash.get('metric');
  if (metricName === undefined) {
    appendMessage(statusElem, "Missing metric name in URL hash.");
    return;
  }

  // Add title and page element
  var title = metricName + ': pairs of variables';
  document.title = title;
  var pageTitleElem = document.getElementById('pageTitle');
  pageTitleElem.innerHTML = title;

  // Add correct links.
  var u = document.getElementById('underlying-status');
  u.href = 'cooked/' + metricName + '/metric-status.csv';

  var csvPath = 'cooked/' + metricName + '/metric-status.part.html';
  ajaxGet(csvPath, statusElem, function(xhr) {
    var elem = document.getElementById('metric_table');
    elem.innerHTML = xhr.responseText;
    makeTablesSortable(urlHash, [elem], tableStates);
    updateTables(urlHash, tableStates, statusElem);
  });
}

// Function to help us find the *.part.html files.
//
// NOTE: This naming convention matches the one defined in task_spec.py
// AssocTaskSpec.
function formatAssocRelPath(metricName, var1, var2) {
  var varDir = var1 + '_X_' + var2.replace('..', '_');
  return metricName + '/' + varDir;
}

// for assoc-pair.html
function initAssocPair(urlHash, tableStates, statusElem, globals) {

  var metricName = urlHash.get('metric');
  if (metricName === undefined) {
    appendMessage(statusElem, "Missing metric name in URL hash.");
    return;
  }
  var var1 = urlHash.get('var1');
  if (var1 === undefined) {
    appendMessage(statusElem, "Missing var1 in URL hash.");
    return;
  }
  var var2 = urlHash.get('var2');
  if (var2 === undefined) {
    appendMessage(statusElem, "Missing var2 in URL hash.");
    return;
  }

  var relPath = formatAssocRelPath(metricName, var1, var2);

  // Add title and page element
  var title = metricName + ': ' + var1 + ' vs. ' + var2;
  document.title = title;
  var pageTitleElem = document.getElementById('pageTitle');
  pageTitleElem.innerHTML = title;

  // Add correct links.
  var u = document.getElementById('underlying-status');
  u.href = 'cooked/' + relPath + '/pair-status.csv';

  /*
  var distUrl = 'cooked/' + metricName + '/dist.csv';
  var u2 = document.getElementById('underlying-dist');
  u2.href = distUrl;
  */

  var tableUrl = 'cooked/' + relPath + '/pair-status.part.html';
  ajaxGet(tableUrl, statusElem, function(xhr) {
    var htmlData = xhr.responseText;
    var elem = document.getElementById('status_table');
    elem.innerHTML = htmlData;

    makeTablesSortable(urlHash, [elem], tableStates);
    updateTables(urlHash, tableStates, statusElem);
  });
}

// for assoc-day.html.
function initAssocDay(urlHash, tableStates, statusElem) {
  var jobId = urlHash.get('jobId');
  var metricName = urlHash.get('metric');
  var var1 = urlHash.get('var1');
  var var2 = urlHash.get('var2');
  var date = urlHash.get('date');

  var err = '';
  if (!jobId) {
    err = 'jobId missing from hash';
  }
  if (!metricName) {
    err = 'metric missing from hash';
  }
  if (!var1) {
    err = 'var1 missing from hash';
  }
  if (!var2) {
    err = 'var2 missing from hash';
  }
  if (!date) {
    err = 'date missing from hash';
  }
  if (err) {
    appendMessage(statusElem, err);
  }

  // Add title and page element
  var titleStr = metricName + ': ' + var1 + ' vs. ' + var2 + ' on ' + date;
  document.title = titleStr;
  var mElem = document.getElementById('metricDay');
  mElem.innerHTML = titleStr;

  var relPath = formatAssocRelPath(metricName, var1, var2);

  // Add correct links.
  var u = document.getElementById('underlying');
  u.href = '../' + jobId + '/raw/' + relPath + '/' + date +
           '/assoc-results.csv';

  var url = '../' + jobId + '/cooked/' + relPath + '/' + date + '.part.html';
  ajaxGet(url, statusElem, function(xhr) {
    var htmlData = xhr.responseText;
    var elem = document.getElementById('results_table');
    elem.innerHTML = htmlData;
    makeTablesSortable(urlHash, [elem], tableStates);
    updateTables(urlHash, tableStates, statusElem);
  });
}

// This is the onhashchange handler of *all* HTML files.
function onHashChange(urlHash, tableStates, statusElem) {
  updateTables(urlHash, tableStates, statusElem);
}
