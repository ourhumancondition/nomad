"use strict";

const { handleWhere } = require("../location_broker/where");

module.exports = (req, res) => handleWhere(req, res);
