Scholarship #1 Group #5 
Azure Load Balancer and Backup Scenario 
Scenario Overview: A company, WebServe Solutions, operates two critical applications 
that are hosted on separate virtual machines (VMs) in Azure. To ensure high availability, the 
company wants to implement an Azure Load Balancer to distribute traƯic between the 
VMs. Additionally, the company needs a robust backup solution to protect the applications 
and their data, and a logging mechanism to store and monitor application logs for 
operational insights and troubleshooting. 
Your task as an Azure Administrator is to design and demonstrate how to implement these 
requirements by using an Azure Load Balancer for traƯic distribution, setting up an 
automated backup solution, and configuring log storage for the two applications. 
Goals: 
1. Implement Azure Load Balancer: Demonstrate the configuration and usage of 
Azure Load Balancer to evenly distribute traƯic between the two applications 
hosted on separate virtual machines. 
2. Backup Solution for Applications: Design and implement a backup strategy for 
both applications to ensure data protection and easy recovery in case of failure. 
3. Store Application Logs: Set up a logging solution to capture and store application 
logs, ensuring that logs are accessible for monitoring, troubleshooting, and auditing 
purposes. 
Student Notes: 
 Load Balancer Configuration: Set up an Azure Load Balancer to distribute 
incoming traƯic between the two VMs hosting the applications. Consider 
configuring health probes to monitor the health of each VM, ensuring traƯic is only 
directed to healthy instances. 
 Application Backup Strategy: You must design a backup plan for the two 
applications running on the VMs. 
 Logging and Monitoring: Implement a solution to collect, store, and manage logs 
for both applications. 
Important Considerations: 
 Load Balancer Design: Consider the diƯerent types of load balancers (public and 
internal) based on the applications' requirements. 
 Backup Solution: The backup solution must ensure that both the applications and 
the VMs they are hosted on are protected. This includes VM snapshots, applicationlevel backups, and database backups if necessary. 
 Log Management: Ensure that logs from both VMs are stored in a centralized 
location. 
 Cost Optimization
Expectations: 
 Load Balancer Demonstration: Students should demonstrate how Azure Load 
Balancer works by configuring it to distribute traƯic across the two VMs. 
 Backup Solution Implementation: They must demonstrate how to schedule 
backups and how to restore applications or VMs from backups in case of failure. 
 Log Storage and Monitoring: Students should set up a logging solution that 
captures application and system logs from both VMs. Scenario Summary: 
In this scenario, students will design and implement a highly available solution using Azure 
Load Balancer, ensure data protection with a robust backup solution, and set up 
centralized log storage and monitoring for the applications hosted on Azure VMs. 