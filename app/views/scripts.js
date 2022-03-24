document.addEventListener("DOMContentLoaded", () => {
  const COMPONENT_COLORS = {
    queue: "#AED581",
    middleware: "#BA68C8",
    memcache: "#4DD0E1",
    redis: "#E57373",
    database: "#FFD54F",
    mongodb: "#A1887F",
    cassandra: "#4DB6AC",
    rabbitmq: "#F06292",
    elasticsearch: "#FF8A65",
    http: "#90A4AE",
    app: "#64B5F6"
  };
  const OTHER_COMPONENT_COLORS = ["#81C784", "#4FC3F7", "#FFF176", "#7986CB", "#9575CD", "#FFB74D", "#DCE775"];

  // Update all charts on the page.
  function updateCharts(updateLocation) {
    const selectedHost = param("host");
    const charts = document.getElementById("charts");
    const minutes = parseInt(selectedValue(document.getElementById("minutes")), 10);
    const hostMenu = document.getElementById("host");
    const actionMenu = document.getElementById("action");
    const aggregated = (minutes >= 24 * 60);

    charts.style.display = "none";

    if (aggregated) {
      hostMenu.selectedIndex = 0;
      hostMenu.disabled = true;
      select2Menus["host"].disable();
      actionMenu.selectedIndex = 0;
      actionMenu.disabled = true;
      select2Menus["action"].disable();
    } else {
      hostMenu.disabled = false;
      select2Menus["host"].enable();
      actionMenu.disabled = false;
      select2Menus["action"].enable();
    }

    document.getElementById("show-error-details").style.display = (selectedHost || aggregated ? "none" : null);
    document.getElementById("error-details").style.display = "none";
    document.getElementById("show-action-details").style.display = (selectedHost || aggregated ? "none" : null);
    document.getElementById("action-details").style.display = "none";

    if (updateLocation !== false) {
      updateWindowLocation();
    }

    currentParams = selectedParams()
    callAPI("metrics", currentParams, "loading-spinner", (data) => {
      charts.style.display = "block";
      updateMetricData(data);
      const live = document.getElementById("live");
      if (live.checked && liveUpdateId === null) {
        liveUpdateId = setInterval(liveUpdate, 1000 * 10);
      }

      document.getElementById("previous").disabled = false;
      if (live.checked || document.getElementById("time").value === "") {
        document.getElementById("next").disabled = true;
      } else {
        document.getElementById("next").disabled = false;
      }
    });
  }

  // Handler called by setInterval for live updates to charts.
  function liveUpdate() {
    if (document.getElementById("live").checked == false || metricData === null || metricData.times.length == 0) {
      return;
    }

    const params = new URLSearchParams();
    ["env", "app", "host", "action", "minutes"].forEach((name) => {
      if (metricData[name] !== null && metricData[name] !== "") {
        params.set(name, metricData[name]);
      }
    });
    params.set("measurement", selectedValue(document.getElementById("measurement")));
    params.set("live_time", metricData.times[metricData.times.length - 1].toISOString());
    callAPI("live_metrics", params, null, (data) => {
      if (data && data.times && data.times.length > 0) {
        updateMetricData(data);
      }
    });
  }

  function updateChartsOnZoom(eventData) {
    const startTimeStr = eventData["xaxis.range[0]"];
    const endTimeStr = eventData["xaxis.range[1]"];
    if (!(startTimeStr && endTimeStr)) {
      return;
    }
    const startTime = Date.parse(startTimeStr.replace(" ", "T"));
    const endTime = Date.parse(endTimeStr.replace(" ", "T"));
    if (startTime === NaN || endTime === NaN) {
      return;
    }
    let minutes = Math.round((endTime - startTime) / 60000);
    if (!minutes || minutes <= 0) {
      return;
    }
    setTime(new Date(startTime));
    setMinutes(minutes)
    updateCharts();
  }

  // Update the charts that are based on metrics data.
  function updateMetricData(data) {
    setMenuOptions("host", data.hosts);
    setMenuOptions("action", data.actions);

    for (let i = 0; i < data.times.length; i++) {
      data.times[i] = new Date(data.times[i]);
    }
    const startTime = data.times[0];
    const endTime = new Date(data.times[data.times.length - 1].getTime() + (data.interval_minutes * 60000));
    document.getElementById("start-time").innerText = new Intl.DateTimeFormat(navigator.language, { month: "short", day: "numeric", year: "numeric", hour: "numeric", minute: "numeric"}).format(startTime);
    document.getElementById("end-time").innerText = new Intl.DateTimeFormat(navigator.language, { month: "short", day: "numeric", year: "numeric", hour: "numeric", minute: "numeric", timeZoneName: "short"}).format(endTime);

    metricData = data;
    plotRequestTime();
    plotThroughput();
    plotErrorRate();
    plotErrorCounts();
  }

  // Update the location href to match the state of the form fields.
  function updateWindowLocation() {
    const params = new URLSearchParams();
    ["env", "app", "host", "action", "minutes", "measurement"].forEach((name) => {
      const element = document.getElementById(name);
      const value = selectedValue(element);
      if (value && value !== "") {
        params.set(name, value);
      }
    });
    if (document.getElementById("live").checked) {
      params.set("live", "1");
    } else {
      const time = timePicker.selectedDates[0];
      if (time) {
        params.set("time", time.toISOString());
      } else {
        params.delete("time");
      }
    }

    window.history.pushState("", document.title, window.location.pathname + "?" + params.toString());
  }

  // Hide or show the time form field based on the value of the live checkbox.
  function updateDisplayOfLiveOrTime(liveUpdated) {
    const minutes = parseInt(selectedValue(document.getElementById("minutes")), 10);
    const liveCheckboxContainer = document.getElementById("live-checkbox");
    const liveCheckbox = document.getElementById("live");
    const timeInput = document.getElementById("time");
    const mobileTimeInput = document.querySelector(".flatpickr-mobile");
    const updateChartsBtn = document.getElementById("update-charts");
    if (minutes > 60) {
      liveCheckboxContainer.style.display = "none";
      liveCheckbox.checked = false;
      timeInput.style.display = null;
      if (mobileTimeInput) {
        mobileTimeInput.style.display = null;
      }
      updateChartsBtn.style.display = null;
    } else {
      liveCheckboxContainer.style.display = null;
      if (liveCheckbox.checked) {
        timeInput.style.display = "none";
        if (mobileTimeInput) {
          mobileTimeInput.style.display = "none";
        }
        updateChartsBtn.style.display = "none";
      } else {
        timeInput.style.display = null;
        if (mobileTimeInput) {
          mobileTimeInput.style.display = null;
        }
        updateChartsBtn.style.display = null;
        if (liveUpdated) {
          if (metricData && metricData.times && metricData.times.length > 0) {
            setTime(metricData.times[0])
          } else {
            timeInput.value = "";
          }
        }
      }
    }
  }

  // Plot the request time chart.
  function plotRequestTime() {
    const measurement = (param("measurement") || "avg");
    const measurementData = metricData[measurement];
    document.getElementById("avg-request-time").innerText = measurementData.avg.toLocaleString();
    let interval = metricData.interval_minutes;
    let units = "minute";
    if (interval == 60) {
      interval = 1;
      units = "hour"
    } else if (interval == 60 * 24) {
      interval = 1
      units = "day"
    }
    document.getElementById("interval-minutes").innerText = "" + interval + " " + units;
    const data = [];
    if (measurement === "avg") {
      if (Object.keys(measurementData.data).length > 0) {
        forEachComponentColor(Object.keys(measurementData.data), (name, color) => {
          data.push({
            name: name,
            type: "bar",
            marker: {
              color: color
            },
            hovertemplate: name + " - %{y:,}ms; %{text} calls/request; %{x} (" + metricData.interval_minutes + "m)",
            textposition: "none",
            x: metricData.times,
            y: measurementData.data[name]["time"],
            text: measurementData.data[name]["count"]
          });
        });
      } else {
        data.push({
          name: measurement,
          type: "bar",
          marker: {
            color: "#00838F"
          },
          x: metricData.times,
          y: metricData.times.map((t) => { return 0 })
        });
      }
    } else {
      data.push({
        name: measurement,
        type: "bar",
        marker: {
          color: "#00838F"
        },
        hovertemplate: "" + metricData.interval_minutes + "m: %{x} %{y:,}ms",
        x: metricData.times,
        y: measurementData.data
      });
    }

    const layout = {
      barmode: "stack",
      xaxis: {
        tickformat: "%I:%M%p\n%b %e, %Y"
      },
      yaxis: {
        title: measurement + " ms",
        fixedrange: true
      },
      margin: {
        t: 10,
        b: 50
      }
    };

    const div = document.getElementById("request-timing");
    Plotly.newPlot(div, data, layout, {displayModeBar: false, responsive: true});
    div.on('plotly_relayout', updateChartsOnZoom);
  }

  // Plot the throughput chart.
  function plotThroughput() {
    document.getElementById("avg-requests-per-minute").innerText = metricData.throughput.avg.toLocaleString();
    const data = {
      name: "request / minute",
      type: "bar",
      marker: {
        color: "#3949AB"
      },
      hovertemplate: "%{y:,} requests / minute; %{x} (" + metricData.interval_minutes + "m)",
      x: metricData.times,
      y: metricData.throughput.data,
    }
    const layout = {
      xaxis: {
        tickformat: "%I:%M%p\n%b %e, %Y"
      },
      yaxis: {
        title: "Request / Minute",
        fixedrange: true
      },
      margin: {
        t: 10,
        b: 50
      }
    };
    const div = document.getElementById("throughput");
    Plotly.newPlot(div, [data], layout, {displayModeBar: false, responsive: true});
    div.on('plotly_relayout', updateChartsOnZoom);
  }

  // Plot the error count chart.
  function plotErrorCounts() {
    document.getElementById("avg-errors-per-minute").innerText = metricData.errors.avg.toLocaleString();
    const data = {
      name: "errors",
      type: "bar",
      marker: {
        color: "#D32F2F"
      },
      hovertemplate: "%{y:,} errors; %{x} (" + metricData.interval_minutes + "m)",
      x: metricData.times,
      y: metricData.errors.data,
    }
    const layout = {
      xaxis: {
        tickformat: "%I:%M%p\n%b %e, %Y"
      },
      yaxis: {
        title: "Errors",
        fixedrange: true
      },
      margin: {
        t: 10,
        b: 50
      }
    };
    const div = document.getElementById("error-count");
    Plotly.newPlot(div, [data], layout, {displayModeBar: false, responsive: true});
    div.on('plotly_relayout', updateChartsOnZoom);
  }

  // Plot the error rate chart.
  function plotErrorRate() {
    const avgErrorRateStr = metricData.error_rate.avg.toLocaleString(navigator.language, {style: "percent", minimumFractionDigits: 2});
    document.getElementById("avg-error-rate").innerText = avgErrorRateStr;
    const data = {
      name: "error rate",
      type: "line",
      marker: {
        color: "#D32F2F"
      },
      hovertemplate: "%{y:.3f} / minute; %{x} (" + metricData.interval_minutes + "m)",
      x: metricData.times,
      y: metricData.error_rate.data,
    }
    const layout = {
      xaxis: {
        tickformat: "%I:%M%p\n%b %e, %Y"
      },
      yaxis: {
        tickformat: ".3%",
        fixedrange: true
      },
      margin: {
        t: 10,
        b: 50
      }
    }
    const div = document.getElementById("error-rate");
    Plotly.newPlot(div, [data], layout, {displayModeBar: false, responsive: true});
    div.on('plotly_relayout', updateChartsOnZoom);
  }

  // Plot the action load percentages chart.
  function plotActionLoad() {
    const actions = [];
    const loads = [];
    const n = (actionData.actions.length < 25 ? actionData.actions.length : 25);
    for (let i = 0; i < n; i++) {
      actions.push(actionData.actions[i].name);
      loads.push(actionData.actions[i].load);
    }
    actions.reverse();
    loads.reverse();
    const data = {
      name: "actions",
      type: "bar",
      orientation: "h",
      marker: {
        color: "#00796B"
      },
      y: actions,
      x: loads
    }
    const layout = {
      autosize: false,
      width: document.getElementById("action-load").clientWidth,
      height: 180 + (actions.length * 25),
      xaxis: {
        tickformat: ".1%",
        fixedrange: true
      },
      yaxis: {
        automargin: true,
        fixedrange: true
      },
      margin: {
        t: 10,
        b: 50
      }
    }
    Plotly.newPlot('action-load', [data], layout, {displayModeBar: false, responsive: true});
  }

  // Show captured error information in a table.
  function showErrors() {
    const rowTemplate = document.getElementById("error-table-row");
    const tbody = document.getElementById("error-table").querySelector("tbody");
    tbody.innerHTML = "";
    errorData.errors.forEach((error) => {
      const template = document.createElement('template');
      template.innerHTML = rowTemplate.innerHTML.trim();
      const row = template.content.firstChild;
      let errorDescription = error.class_name;
      if (error.message && error.message !== "") {
        errorDescription += " (" + error.message + ")";
      }
      row.querySelector(".error-class-name").innerText = errorDescription;
      row.querySelector(".error-count").innerText = error.count;
      const backtrace = row.querySelector(".error-backtrace");
      error.backtrace.forEach((line) => {
        const div = document.createElement("div");
        div.classList.add("backtrace-line")
        div.innerText = line;
        backtrace.append(div);
      })
      tbody.append(row);
    });
  }

  // Iterate over components with consistent colors for well know components.
  function forEachComponentColor(names, callback) {
    const usedNames = {};
    Object.keys(COMPONENT_COLORS).forEach((name) => {
      if (names.includes(name)) {
        usedNames[name] = true;
        callback(name, COMPONENT_COLORS[name]);
      }
    });
    index = 0;
    names.forEach((name) => {
      if (!usedNames[name]) {
        const color = OTHER_COMPONENT_COLORS[index % OTHER_COMPONENT_COLORS.length];
        callback(name, color);
      }
    });
  }

  // Return a query parameter by name.
  function param(name) {
    return new URLSearchParams(window.location.search).get(name);
  }

  // Serialize the current form state into query parameters.
  function selectedParams() {
    const params = new URLSearchParams();
    ["env", "app", "host", "action", "minutes"].forEach((name) => {
      params.set(name, selectedValue(document.getElementById(name)));
    });
    if (!document.getElementById("live").checked) {
      const time = timePicker.selectedDates[0]
      if (time) {
        params.set("time", time.toISOString());
      } else {
        params.delete("time")
      }
    }
    return params
  }

  // Get the current value from a form element.
  function selectedValue(element) {
    if (element.type === "select-one") {
      const option = element.options[element.selectedIndex];
      if (option) {
        return option.value;
      } else {
        return "";
      }
    } else if (element.type === "checkbox") {
      if (element.checked) {
        return element.value;
      } else {
        return null;
      }
    } else {
      return element.value;
    }
  }

  // Set the value of a form element.
  function setSelectedValue(paramName) {
    const value = (param(paramName) || "");
    const element = document.getElementById(paramName);
    if (element.type === "select-one") {
      for (let i = 0; i < element.options.length; i++) {
        if (element.options[i].value === value) {
          element.selectedIndex = i;
          setSelect2Value(paramName);
          break;
        }
      }
    } else if (element.type === "checkbox") {
      element.checked = (value === "1");
    } else if (paramName === "time") {
      if (value && value !== "") {
        const time = new Date(Date.parse(value));
        timePicker.setDate(time);
      } else {
        element.value = "";
      }
    } else {
      element.value = value;
    }
  }

  function setSelect2Value(id) {
    const select2 = select2Menus[id];
    if (!select2) {
      return;
    }
    const selectedIndex = document.getElementById(id).selectedIndex;
    select2.selectedOptions = [select2.options[selectedIndex]];
    for (let i = 0; i < select2.options.length; i++) {
      if (i === selectedIndex) {
        select2.options[i].element.classList.add("selected");
      } else {
        select2.options[i].element.classList.remove("selected");
      }
    }
    select2._renderSelectedItems();
  }

  // Set menu options on a select element to the specified values. Options with
  // empty values will be retained since these are for "All" selectors.
  function setMenuOptions(id, values) {
    const menu = document.getElementById(id);
    const selection = param(id);
    if (selection && values.indexOf(selection) < 0) {
      values.push(selection);
    }
    while (menu.options.length > 0 && menu.options[menu.options.length - 1].value !== "") {
      menu.options.remove(menu.options.length - 1)
    }
    values.forEach((value) => {
      const option = document.createElement("option");
      option.value = value;
      option.text = value;
      menu.options.add(option);
      if (selection === value) {
        menu.selectedIndex = menu.options.length - 1;
      }
    });
    select2Menus[id].update();
    setSelect2Value(id);
  }

  // Set the time field from a Date object.
  function setTime(date) {
    if (!date) {
      timePicker.clear();
    } else {
      if (typeof date === "string") {
        date = new Date(Date.parse(value));
      }
      timePicker.setDate(date);
    }
  }

  function setMinutes(value) {
    if (!value) {
      value = 30;
    }
    value = "" + value;
    const minutes = document.getElementById("minutes");
    let foundIndex = -1;
    for (let i = 0; i < minutes.options.length; i++) {
      const option = minutes.options[i];
      if (option.value === value) {
        foundIndex = i;
        break;
      }
    }
    if (foundIndex < 0) {
      const customOption = document.createElement("option");
      customOption.value = value;
      customOption.innerText = value + " minutes";
      customOption.classList.add("custom-minutes");
      minutes.prepend(customOption);
      foundIndex = 0
    }
    minutes.selectedIndex = foundIndex;
    removeCustomMinutes();
    select2Menus.minutes.update();
    setSelect2Value("minutes");
  }

  function removeCustomMinutes() {
    document.querySelectorAll("#minutes .custom-minutes").forEach((element) => {
      if (!element.selected) {
        element.remove();
      }
    });
  }

  // Pad a number with the specified number of zeros.
  function lpadNumber(number) {
    const padded = "0" + number;
    return padded.substring(padded.length - 2, padded.length);
  }

  // Get the URL for making API calls.
  function apiURL(action, params) {
    let url = window.location.pathname;
    if (!url.endsWith("/")) {
      url += "/";
    }
    url += action + "?" + params.toString();
    return url;
  }

  // Call the API with the path and params specified. If spinnerId is provided,
  // that element will be shown and then hidden to indicate something is happening.
  // The callback function will be called with the API response.
  function callAPI(path, params, spinnerId, callback) {
    const spinner = (spinnerId ? document.getElementById(spinnerId) : null);

    const fetchOptions = {credentials: "same-origin"};
    const headers = new Headers({"Accept": "application/json"});
    const accessToken = window.sessionStorage.getItem("access_token")
    if (accessToken) {
      headers["Authorization"] = "Bearer " + accessToken;
    }
    fetchOptions["headers"] = headers;
    const url = apiURL(path, params);

    if (spinner) {
      spinner.style.display = "block";
    }

    fetch(url, fetchOptions)
    .then((response) => {
      if (response.ok) {
        return response.json();
      } else {
        throw(response)
      }
    })
    .then(callback)
    .then(hideAlert)
    .catch((error) => {
      console.error(error)
      if (error.status === 401 || error.status === 403) {
        if (authenticationUrl()) {
          window.location = authenticationUrl();
        } else {
          showAlert("Access denied. You need to re-authenticate to continue.");
        }
      } else {
        showAlert("Sorry, an error occurred fetching data.");
      }
    })
    .finally(() => {
      if (spinner) {
        spinner.style.display = "none";
      }
    });
  }

  // Support integration into single page applications where OAuth2 access tokens are used.
  // The access token can be passed either in the access_token query parameter per the
  // OAuth2 standard, or in the URL hash. Passing it in the hash will prevent it from ever
  // being sent to the backend and is a bit more secure since there's no chance a web server
  // will accidentally log it with the request URL.
  function storeAccessToken() {
    let accessToken = null;
    if (param("access_token")) {
      accessToken = param("access_token");
    }
    if (window.location.hash.startsWith("#access_token=")) {
      accessToken = window.location.hash.replace("#access_token=", "");
    }
    if (accessToken) {
      window.sessionStorage.setItem("access_token", accessToken);
      const params = new URLSearchParams(window.location.search);
      params.delete("access_token");
      window.location.hash = null;
      window.history.replaceState("", document.title, window.location.pathname + "?" + params.toString());
    }
  }

  // Generate a CSV dump of the current data.
  function generateCSV() {
    const rows = []
    const componentNames = Object.keys(metricData.avg.data);
    const headers = ["time", "requests per minute", "errors", "error rate", "p50 request time", "p90 request time", "p99 request time", "average request time"]
    componentNames.forEach((name) => {
      headers.push("average " + name + " time");
      headers.push("average " + name + " count");
    });
    rows.push(headers);
    for (let i = 0; i < metricData.times.length; i += 1) {
      const row = [metricData.times[i], metricData.throughput.data[i], metricData.errors.data[i], metricData.error_rate.data[i], metricData.p50.data[i], metricData.p90.data[i], metricData.p99.data[i]];
      let total = 0;
      let componentData = [];
      componentNames.forEach((name) => {
        const t = metricData.avg.data[name]["time"][i];
        const c = metricData.avg.data[name]["count"][i];
        componentData.push(t);
        componentData.push(c);
        total += t;
      });
      row.push(total);
      rows.push(row.concat(componentData));
    }
    return rows.join("\n")
  }

  function showAlert(message) {
    const alertDiv = document.getElementById("alert");
    alertDiv.innerText = message;
    alertDiv.style.display = "block";
  }

  function hideAlert() {
    document.getElementById("alert").style.display = "none";
  }

  // Show a modal window overlayed on the page.
  function showModal() {
    const modal = document.querySelector("#modal");
    modal.style.display = "block";
    modal.setAttribute("aria-hidden", "false");
    modal.activator = document.activeElement;
    focusableElements(document).forEach(function(element) {
      if (!modal.contains(element)) {
        element.dataset.saveTabIndex = element.getAttribute("tabindex");
        element.setAttribute("tabindex", -1);
      }
    });
    document.querySelector("body").style.overflow = "hidden";
  }

  // Hide the modal window overlayed on the page.
  function hideModal() {
    const modal = document.querySelector("#modal");
    modal.style.display = "none";
    modal.setAttribute("aria-hidden", "true");
    focusableElements(document).forEach(function(element) {
      const tabIndex = element.dataset.saveTabIndex;
      delete element.dataset.saveTabIndex;
      if (tabIndex) {
        element.setAttribute("tabindex", tabIndex);
      }
    });
    if (modal.activator) {
      modal.activator.focus();
      delete modal.activator;
    }
    document.querySelector("body").style.overflow = "visible";
  }

  // Returns a list of all focusable elements so that they can be set to not take the focus
  // when a modal is opened.
  function focusableElements(parent) {
    return parent.querySelectorAll("a[href], area[href], button, input:not([type=hidden]), select, textarea, iframe, [tabindex], [contentEditable=true]")
  }

  function authenticationUrl() {
    document.querySelector("body").dataset["authenticationUrl"];
  }

  // Add event listeners.
  document.getElementById("update-charts").addEventListener("click", (event) => {
    updateCharts();
  });

  document.getElementById("previous").addEventListener("click", (event) => {
    document.getElementById("live").checked = false;
    const time = new Date(metricData.times[0].getTime() - (metricData.minutes * 60000));
    setTime(time);
    updateCharts();
  });

  document.getElementById("next").addEventListener("click", (event) => {
    document.getElementById("live").checked = false;
    const time = new Date(metricData.times[metricData.times.length - 1].getTime() + (metricData.interval_minutes * 60000));
    setTime(time);
    updateCharts();
  });

  document.getElementById("env").addEventListener("change", () => {
    document.getElementById("host").selectedIndex = 0;
    document.getElementById("action").selectedIndex = 0;
    updateCharts();
  });
  document.getElementById("app").addEventListener("change", () => {
    document.getElementById("host").selectedIndex = 0;
    document.getElementById("action").selectedIndex = 0;
    updateCharts();
  });
  document.getElementById("host").addEventListener("change", () => {
    updateCharts();
  });
  document.getElementById("action").addEventListener("change", () => {
    updateCharts();
  });
  document.getElementById("time").addEventListener("change", () => {
    updateCharts();
  });
  document.getElementById("live").addEventListener("change", () => {
    updateDisplayOfLiveOrTime(true);
    updateCharts();
  });
  document.getElementById("minutes").addEventListener("change", () => {
    updateDisplayOfLiveOrTime(false);
    removeCustomMinutes();
    updateCharts();
  });

  document.getElementById("measurement").addEventListener("change", (event) => {
    updateWindowLocation();
    plotRequestTime();
  });

  document.getElementById("show-error-details").addEventListener("click", (event) => {
    event.target.style.display = "none";
    callAPI("errors", currentParams, "details-loading-spinner", (data) => {
      errorData = data;
      document.getElementById("error-details").style.display = "block";
      showErrors();
    });
  });

  document.getElementById("show-action-details").addEventListener("click", (event) => {
    event.target.style.display = "none";
    const params = new URLSearchParams(window.location.search);
    callAPI("actions", currentParams, "details-loading-spinner", (data) => {
      actionData = data;
      document.getElementById("action-details").style.display = "block";
      plotActionLoad();
    });
  });

  document.getElementById("download-data").addEventListener("click", (event) => {
    const link = document.createElement("a");
    const blob = new Blob([generateCSV()],{type: "text/csv; charset=utf-8;"});
    const url = URL.createObjectURL(blob);
    link.href = url;
    link.setAttribute("download", "apm-data.csv");
    link.click();
  });

  document.getElementById("help").addEventListener("click", (event) => {
    event.preventDefault();
    showModal();
  });

  document.getElementById("modal").addEventListener("click", (event) => {
    if (event.target.classList.contains("js-close-modal")) {
      event.preventDefault();
      hideModal();
    }
  });

  function initializeSettings() {
    // Set up default values from the current page URL.
    setSelectedValue("env");
    setSelectedValue("app");
    setSelectedValue("host");
    setSelectedValue("action");
    setMinutes(param("minutes"));
    setSelectedValue("live");
    if (document.getElementById("live").checked) {
      document.getElementById("time").value = "";
      document.getElementById("time").style.display = "none";
    } else {
      setSelectedValue("time");
    }
    setSelectedValue("measurement");
    updateDisplayOfLiveOrTime(false);
    updateCharts(false);
  }

  window.addEventListener("popstate", initializeSettings);

  // Initialize the application
  let metricData = null;
  let errorData = null;
  let actionData = null;
  let liveUpdateId = null;
  let currentParams = null;

  const select2Menus = {}
  document.querySelectorAll("select").forEach((select) => {
    const searchable = select.dataset.searchable;
    const select2 = NiceSelect.bind(select, {searchable: searchable});
    if (select.id) {
      select2Menus[select.id] = select2;
    }
  });

  const timePicker = flatpickr("#time", {
    enableTime: true,
    dateFormat: "M j, Y, h:iK"
  });

  storeAccessToken();
  initializeSettings();
});
