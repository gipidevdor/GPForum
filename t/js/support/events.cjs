/* SPDX-FileCopyrightText: 2026 GPForum Contributors
 * SPDX-License-Identifier: BSD-3-Clause */
"use strict";

// Keep listener ordering, multiple listeners, once and cancellation in Node's
// EventTarget instead of reimplementing them in each DOM fixture. This is not
// a DOM tree: bubbling and layout remain the browser tier's responsibility.
function eventTarget() {
  return Object.assign(new EventTarget(), {
    emit(type, properties = {}) {
      const event = new Event(type, {cancelable: true});
      for (const [name, value] of Object.entries(properties)) {
        Object.defineProperty(event, name, {value, configurable: true, writable: true});
      }
      this.dispatchEvent(event);
      return event;
    },
  });
}

module.exports = {eventTarget};
