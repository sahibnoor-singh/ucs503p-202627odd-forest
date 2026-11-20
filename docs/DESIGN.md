# Design and analysis models

These are the models of the implemented FOREST system. Each one is explained in the final report ([PDF](../project-report-final/FOREST_Final_Report.pdf), [Word](../project-report-final/FOREST_Final_Report.docx)).

## Use cases

![Use case diagram](../assets/diagrams/usecase.png)

The User can both watch and create. The Moderator reviews reports. The Gemini API and the Email service are outside systems that take part.

## Workflow and data flow

![Activity diagram for a reply](../assets/diagrams/activity_reply.png)

![Swimlane diagram for posting a video](../assets/diagrams/activity.png)

![Data flow diagram, level 0](../assets/diagrams/dfd0.png)

![Data flow diagram, level 1](../assets/diagrams/dfd1.png)

![Data flow diagram, level 2](../assets/diagrams/dfd2.png)

## Architecture

![Layered architecture](../assets/diagrams/architecture.png)

Clients talk only to the server through Caddy, which handles HTTPS. The server is one process with a SQLite database and an upload folder, and it calls the Gemini API and an email provider.

## Class diagrams

![Class diagram of the data entities](../assets/diagrams/classdiagram.png)

![Class diagram of the server services](../assets/diagrams/class_services.png)

## Sequence diagrams

![Posting and analysing a video](../assets/diagrams/sequence.png)

![Signing up with an email code](../assets/diagrams/sequence2.png)

![Hiding an own video](../assets/diagrams/sequence3.png)

## Collaboration diagrams

![Replying to a post](../assets/diagrams/collab1.png)

![Hiding an own video](../assets/diagrams/collab2.png)

## State charts

![State of a post](../assets/diagrams/state.png)

![State of an account](../assets/diagrams/state_account.png)

![State of a debate room](../assets/diagrams/state_room.png)

## Components, deployment and data

![Component diagram](../assets/diagrams/component.png)

![Deployment diagram](../assets/diagrams/deployment.png)

![Entity relationship diagram](../assets/diagrams/er.png)

## Measurements

![Response time of the main endpoints](../assets/diagrams/bench.png)

Measured on the cloud machine with 2 000 users, 30 395 posts and 120 000 likes. Median and 95th percentile response times in milliseconds.
