<# The purpose of this script is to migrate SCSM Service Level Object.

Pre-requisites: 

1. Workitem Queues must be migrated to SCSM 2019 using MP import
2. Calendar objects must be migrated. A simple Orchestrator runbook is created for this. 
3. Metric objects must be migrated. A simple Orchestrator runbook is created for this. 

I have created an Orchestrator Runbook to migrate SLO, but System.SLA.Group and System.SLA.WorkflowTarget 
are group object, which needs to select specific Related Claess name in Get Reletionship activity. 

Powershell script may help to resolve this issue with New-SCRelationshipInstance 

Here is how the script works:

1. Get SLO from SCSM 2012 R2 with all related objects
2. Create SLO in SCSM 2019
3. Create all related relationships







#>

Import-Module 'C:\Program Files\Microsoft System Center\Service Manager\powershell\System.Center.Service.Manager.psd1'

$sm12server = 'SGSM12MS'
$sm19server = 'SM19DBMS'

$slaconfigclass = Get-SCSMClass -DisplayName "Service Level Configuration" -ComputerName $sm12server
$SLOs = Get-SCSMClassInstance -Class $slaconfigclass -ComputerName $sm12server

$sm19slaclass = Get-SCSMClass -DisplayName "Service Level Configuration" -ComputerName $sm19server
$sm19SLOs = Get-SCSMClassInstance -Class $slaconfigclass -ComputerName $sm19server

foreach ($slo in $SLOs)
{
    
    if ($sm19SLOs.displayname -ccontains  $slo.displayname)
    {
        Write-Host "SLO $($slo.displayname) is already migrated to SCSM 2019"
    }
    else
    {

        Write-Host "Migrating SLO $($slo.displayname) to SCSM 2019"
      
      
        $sloid = $slo.id
        $slodisplayname = $slo.DisplayName
        $slodescription = $slo.Description 
      
    # Interestingly the property has to be in the following format. Otherwise 
    # new-scsmclassinstance will fail.   
        $sm19sloproperty =  @{
                                Id = "$sloId"
                                TypeId = [Guid]($slo.TypeId)
                                DisplayName = "$slodisplayname"
                                Description = "$slodescription"
                       
                             }
    # It is not necessary for now.    
    # [threading.thread]::CurrentThread.CurrentCulture = 'en-US'

        New-SCSMClassInstance -Class $sm19slaclass `
                            -Property $sm19sloproperty `
                            -ComputerName $sm19server
                         
        
        $sm19SLO = Get-SCSMClassInstance -Class $sm19slaclass | ? DisplayName -eq $slo.DisplayName

        $slorels = Get-SCSMRelationshipInstance -SourceInstance $slo -ComputerName $sm12server
        foreach ($rel in $slorels)
        {
            $relobj = $rel.TargetObject
            Write-Host "Related Object from SCSM 2012 $($relobj.displayname) for SLO $($slo.displayname)"

                     
            $relclass = Get-SCSMRelationship -id $rel.RelationshipId -ComputerName $sm12server
            Write-Host $relclass


            $targetclass = Get-SCSMClass -id $relclass.Target.Type.id -ComputerName $sm12server
            Write-Host $targetclass.DisplayName
            
            $sm12target = Get-SCSMClassInstance -class $targetclass -ComputerName $sm12server `
                            | ? displayname -eq $($relobj.displayname)

# Need to get the real class since the previous one from relationship is abstract.                 
            $targetclass = Get-SCSMClass -Instance $sm12target


            if (($relclass.DisplayName -eq 'Target') -or ($relclass.DisplayName -eq 'Warning Threshold'))
            {
                
 
                $targetdisplayname = $sm12target.Displayname
                $targetid = $sm12target.Id
                $targetTimeMeasure = $sm12target.TimeMeasure
                $targetTimeUnits = $sm12target.TimeUnits

                $targetproperty = @{
                        DisplayName = "$targetdisplayname"
                        Id = "$targetid"
                        TimeMeasure = "$targetTimeMeasure"
                        TimeUnits = "$targetTimeUnits"

                    }
                New-SCRelationshipInstance -RelationshipClass $relclass -Source $sm19SLO -TargetClass $targetclass `
                         -TargetProperty $targetproperty -ComputerName $sm19server 
            }
            else
            {
                $sm19targetobj = Get-SCSMClassInstance -Class $targetclass -ComputerName $sm19server `
                                | ? Id -eq $($sm12target.id)
                Write-Host "Get same target object on SCSM 2019 $($sm19targetobj.DisplayName)"

            

            New-SCRelationshipInstance -RelationshipClass $relclass -Source $sm19SLO -Target $sm19targetobj `
                              -ComputerName $sm19server

            }

            Write-Host

        }





    }

}
