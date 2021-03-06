//
//  SKMSchduler.swift
//  Skeem
//
//  Created by Zhu Zhan Yan on 10/10/16.
//  Copyright © 2016 SSTInc. All rights reserved.
//

import UIKit

/*
 * public enum SKMSchedulerError:Error
 * - Describles the errors that may occur when using SKMScheduler
*/
public enum SKMSchedulerError:Error
{
    
case DeadlineOverflow /* Subtasks could not be scheduled before deadline */
    case InsufficentData /* Data not present */
}


/*
 * public class SKMScheduler : NSObject
 * - Determines Schedulable time from void duration
 * - Determines Size of Task to Schedule
 * - Schedules Tasks based on attribute
*/
public class SKMScheduler: NSObject
{
    //Properties
    //Link
    weak var dataCtrl:SKMDataController! /* Link to Data Controller
                                          * NOTE: Will Terminate executable if Missing
                                         */
    weak var config:SKMConfig! /* Link to Config Object
                               * Note: Will Terminate executable if missing */
    var dataViewCtrl:SKMDataController! /*Link to Data View Data controller */
    var dataView:SKMDataView! /*Link to Data View */

    //Status
    var schd_task_date:NSDate! /*Date Schedule was generated*/
    var schd_drsn_date:NSDate! /*Date Duration Schedule was generated*/
    var sch_affinity:Bool! /*Whether Duration Afinity is followed */

    //Data
    var schd_task:[SKMDuration:[SKMTask]]! /* Generated Scheduling of subtask*/
    var schd_drsn:[SKMDuration]! /* Generated Array of Chronologically Ordered Duration */



    //Data
    //Methods
    /*
     * init(datactrl:SKMDataController)
     * [Arguments]
     * datactrl - SKMDataController to link to
    */
    init(dataCtrl:SKMDataController,cfg:SKMConfig)
    {
        self.dataCtrl = dataCtrl
        self.dataView = SKMDataView(db: dataCtrl.DB)
        self.dataViewCtrl = SKMDataController(db: self.dataView)
        self.schd_task_date = NSDate.distantPast as NSDate
        self.sch_affinity = true
        self.schd_task = Dictionary<SKMDuration,Array<SKMTask>>()
        self.config = cfg

        super.init()
    }

    /*
     * public func lastTaskDate() -> NSDate
     * - Determine the last determinable date/time deadline for tasks
     * [Return]
     * NSDate - Last Deadline (Last Date in time determinable)
    */
    public func lastTaskDate() -> NSDate
    {
        self.dataCtrl.updateTask()
        self.dataCtrl.pruneTask()

        if let lastTask = self.dataCtrl.sortedTask(sattr: SKMTaskSort.deadline).last
        {
            return lastTask.deadline
        }
        else
        {
            return NSDate() //Current Date/Time
        }
    }

    /*
     * public func generateSchedulableDuration()
     * - Genrate an Array of SKMDuration where tasks may be scheduled, sorted by time
     * [Return]
     * Array<SKMDuration> - Array of SKMDuration where tasks may be scheduled
    */
    public func generateSchedulableDuration() -> [SKMDuration]
    {
        //Prepare Data View
        self.dataCtrl.updateVoidDuration()
        self.dataCtrl.pruneVoidDuration()
        self.dataView.loadFromDB()

        //Result Data
        var arr_drsn = Array<SKMDuration>()
        
        //Status Data
        
        if self.dataView.retrieveAllEntry(lockey: SKMDBKey.void_duration).count > 0
        {
            var date = Date() //Init to Current Date
            var voidd = self.dataViewCtrl.sortedVoidDuration(sattr: SKMVoidDurationSort.begin)[0] //Closest begin date

            //Extract Duration from Void Duration
            while date.compare(self.lastTaskDate() as Date) == ComparisonResult.orderedAscending && self.dataView.voidDuration.count >= 0

            {
                //date < last task date
                //Duration from date to voidd.begin
                let tint = voidd.begin.timeIntervalSince(date)
                if tint > 0
                {
                    let drsn = SKMDuration(begin: date as NSDate, duration: Int(round(tint)))
                    arr_drsn.append(drsn)
                }

                //Update Data
                let tadd = voidd.duration + 1
                date = (NSDate(timeInterval: TimeInterval(tadd), since: voidd.begin as Date)) as Date //1 Second after voidd
                self.dataView.simulateDate(date: date as NSDate) //Update Repeat Task
                self.dataViewCtrl.pruneVoidDuration()
                voidd = self.dataViewCtrl.sortedVoidDuration(sattr: SKMVoidDurationSort.begin)[0] //Closest begin date
            }

            //Duration from date to last date/time
            let tint = self.lastTaskDate().timeIntervalSince(date)
            if tint > 0
            {
                let drsn = SKMDuration(begin: date as NSDate, duration: Int(round(tint)))
                arr_drsn.append(drsn)
            }

        }

        //Cleanup Data
        self.dataView.loadFromDB()

        return [SKMDuration]()
    }

    /*
     * public func durationLeft(date:NSDate) -> Int
     * - Detemines the schedulable duration left until date in seconds
     * [Return]
     * Int - Schedulable duration until date
    */
    public func durationLeft(date:NSDate) -> Int
    {
        //Prepare Data
        let arr_drsn = self.generateSchedulableDuration()
        var rst_drsn = 0

        for drsn in arr_drsn
        {
            if drsn.begin.compare(date as Date) == ComparisonResult.orderedDescending
            {
                //Duration begin > date
                break
            }
            else if drsn.begin.compare(date as Date) == ComparisonResult.orderedAscending && Date(timeInterval: TimeInterval(drsn.duration), since: drsn.begin as Date).compare(date as Date) == ComparisonResult.orderedDescending
            {
                //Duration begin < date < Durationbegin + duration
                //Duration between Duration begin and date
                rst_drsn += Int(round(date.timeIntervalSince(drsn.begin as Date)))
            }
            else
            {
                //Full Duration
                rst_drsn += drsn.duration
            }
        }

        return rst_drsn
    }

    /*
     * public func generateSubtask(task:SKMTask) -> [SKMTask]
     * - Generate subtasks from task
     * [Return]
     * Array<SKMTask> - Array of subtasks of task, sorted by time
     */
    public func generateSubtask(task:SKMTask) -> [SKMTask]
    {
        //Prepare Data
        var arr_stsk = Array<SKMTask>()
        let stsk_cnt = Int(floor(Double(task.duration / task.duration_affinity)))
        var duration_left = task.duration
        var completion = task.completion

        //Generate Subtasks
        for stsk_idx in 0..<stsk_cnt
        {
            let stsk = SKMTask(name: task.name, deadline: task.deadline, duration:task.duration, duration_affinity: task.duration_affinity, subject: task.subject, description: task.descript)

            if stsk_idx == (stsk_cnt - 1)
            {
                //Last Subtask
                stsk.duration = duration_left
                stsk.completion = 1.0 - completion //Completion left
            }
            else
            {
                stsk.duration = task.duration_affinity
                stsk.completion = Double(task.duration_affinity)/Double(task.duration)
                completion += Double(task.duration_affinity)/Double(task.duration)
            }

            duration_left -= stsk.duration
            arr_stsk.append(stsk)
        }

        return arr_stsk
    }

    /*
     * public func generateAllSubtask() -> [String:[SKMTask]]
     * - Generate subtasks from all tasks
     * [Return]
     * Dictionary<String,Array<SKMTask>> - Dictionary with key as task name and value as subtasks generated from task specfied by name
    */
    public func generateAllSubtask() -> [String:[SKMTask]]
    {
        //Prepare Data View
        self.dataCtrl.updateTask()
        self.dataCtrl.pruneTask()
        self.dataView.loadFromDB()

        //Result Data
        var sch_stsk = Dictionary<String,Array<SKMTask>>()

        //Data Check
        if self.dataView.task.count <= 0
        {
            return sch_stsk
        }

        //Status Data
        var date = Date()
        var task = self.dataViewCtrl.sortedTask(sattr: SKMTaskSort.deadline)[0] //Closest Deadline

        //Iterate Tasks
        while date.compare(self.lastTaskDate() as Date) != ComparisonResult.orderedDescending && self.dataView.task.count > 0
        {
            //Generate Subtask
            let task_stsk = self.generateSubtask(task: task)
            for stsk in task_stsk
            {
                if var arr_stsk = sch_stsk[task.name]
                { arr_stsk.append(stsk)
                    sch_stsk[task.name] = arr_stsk
                }
                else
                {
                    //Subtask array missing
                    var arr_stsk = Array<SKMTask>()
                    arr_stsk.append(stsk)
                    sch_stsk[task.name] = arr_stsk
                }
            }

            //Update Data
            date = (task.deadline.addingTimeInterval(1) as Date)
            self.dataView.simulateDate(date: date as NSDate) //Update Repeat Tasks
            self.dataViewCtrl.pruneTask()
            task = self.dataViewCtrl.sortedTask(sattr: SKMTaskSort.deadline)[0] //Closest Deadline
        }

        //Cleanup Data
        self.dataView.loadFromDB()

        return sch_stsk
    }

    /*
     * public func vaildateSchedulable() -> Bool
     * - Vaildates if scheduling all tasks is possible
     * NOTE: Does not verify if duration affinity can be followed
     * [Return]
     * Bool - Returns true if scheduling all tasks is possible
    */
    public func vaildateSchedulable() -> Bool
    {
        //Generate Input Data
        let tasks = (Array(self.dataCtrl.DB.retrieveAllEntry(lockey: SKMDBKey.task).values) as! Array<SKMTask>)
        var drsn_schd = 0 //Duration that has already been scheduled

        for task in tasks
        {
            //Duration Left to Schedule
            let drsn_left = self.durationLeft(date: task.deadline) - drsn_schd 

            if drsn_left < task.duration
            {
                return false //Cannot fit current task
            }
            else
            {
                drsn_schd += task.duration
            }
        }

        return true
    }

    /*
     * public scheduleTask()
     * - Generate Schedule 
     * - Resultant Schedule has Schedulable Duration as Key and an Array of subtasks scheduled as value.
     * [Return]
     * [SKMDuration:[SKMTask]] - Generated Schedule.
     * [Error]
     * SKMSchedulerError.DeadlineOverflow - Unable to schedule all Tasks before task's repective deadline
    */
    public func scheduleTask() throws -> [SKMDuration:[SKMTask]]
    {
        //Safeguard check
        if self.vaildateSchedulable() == false
        {
            throw SKMSchedulerError.DeadlineOverflow
        }

        //Prepare Data View
        self.dataCtrl.updateTask()
        self.dataCtrl.pruneTask()
        self.dataView.loadFromDB()

        //Generate Input Data
        let arr_drsn = self.generateSchedulableDuration()
        var dict_tsk = (self.dataView.retrieveAllEntry(lockey: SKMDBKey.task) as! [String:SKMTask])
        var arr_tsk = Array(dict_tsk.keys)
        var dict_stsk = self.generateAllSubtask()

        //Result Data
        var schd_task = Dictionary<SKMDuration,Array<SKMTask>>()
        for drsn in arr_drsn
        {
            schd_task[drsn] = Array<SKMTask>()
        }

        //Slack - Duration schedulable till deadline - Duration need by task
        //Slack Sort
        let slk_srt = {(tsk1:String,tsk2:String) -> Bool in
            let tsk1_slk = self.durationLeft(date: dict_tsk[tsk1]!.deadline) - dict_tsk[tsk1]!.duration
            let tsk2_slk = self.durationLeft(date: dict_tsk[tsk2]!.deadline) - dict_tsk[tsk2]!.duration

            return tsk1_slk <= tsk2_slk
        }

        if arr_tsk.count <= 0
        {
            //Status Data
            var tsk_idx = 0
            var tsk = arr_tsk.sorted(by: slk_srt)[tsk_idx]
            var stsk = dict_stsk[tsk]!.removeFirst()
            
            //Schedule Data
            for drsn in arr_drsn
            {
                while drsn.duration > 0 && arr_tsk.count > 0
                {
                    //Duration Check
                    if drsn.duration < stsk.duration && self.sch_affinity == true
                    {
                        //Current Duration is less then subtask duration && Duration affinity following positive
                        if tsk_idx < (arr_tsk.count - 1)
                        {
                            //Task index must be one less then arr_tsk count -1
                            tsk_idx += 1 //Attempt to fit Next Task's subtask
                        }
                        else
                        {
                            //Failed to fit all Task's subtasks
                            break //Attempt Next Duration
                        }
                    }
                    else if drsn.duration < stsk.duration && self.sch_affinity == false
                    {
                        //Current Duration is less then subtask duration && Duration affinty following negative
                        //Split subtask into 2 subtasks
                        //Subtask_1
                        let stsk_1 = (stsk.copy() as! SKMTask)
                        stsk_1.duration = drsn.duration
                        stsk_1.completion = stsk.completion * (Double(stsk_1.duration) / Double(stsk.duration))
                        //Subtask 2
                        let stsk_2 = stsk //Reference
                        stsk_2.duration -= stsk_1.duration
                        stsk_2.completion -= stsk_1.completion

                        //Schedule Subtask 1
                        schd_task[drsn]!.append(stsk_1)

                        //Update Data
                        drsn.duration -= stsk.duration
                        dict_tsk[tsk]!.duration -= stsk_1.duration
                        dict_tsk[tsk]!.completion -= stsk_1.completion

                        //Defer Schedule Subtask 2
                        dict_stsk[tsk]!.insert(stsk_2, at: 0)
                    }
                    else
                    {
                        //Current duration sufficent to schedule subtask
                        schd_task[drsn]!.append(stsk)

                        //Update Data
                        drsn.duration -= stsk.duration
                        dict_tsk[tsk]!.duration -= stsk.duration
                        dict_tsk[tsk]!.completion -= stsk.completion
                        tsk_idx = 0
                    }

                    //Update Data
                    let arr_tsk_cpy = arr_tsk
                    for tsk in arr_tsk_cpy
                    {
                        if dict_stsk[tsk]!.count <= 0
                        {
                            let tsk_i = arr_tsk_cpy.index(of: tsk)!
                            arr_tsk.remove(at: tsk_i)
                        }
                    }

                    if arr_tsk.count > 0
                    {
                        tsk = arr_tsk.sorted(by: slk_srt)[tsk_idx]
                        stsk = dict_stsk[tsk]!.removeFirst()
                    }
                }
            }
        }
        
        //Check for Unscheduled Tasks
        if arr_tsk.count > 0
        {
            if self.sch_affinity == true
            {
                //Attempt to Reschedule without following affinity
                self.sch_affinity = false
                do
                {
                    schd_task = try self.scheduleTask()
                }
                catch SKMSchedulerError.DeadlineOverflow
                {
                    print("Warn:SKMScehduler: Scheduler could not schedule all tasks before deadline")
                    throw SKMSchedulerError.DeadlineOverflow
                }
                catch
                {
                    print("FATAL:SKMScheduler:Unknown Error Occured while scheduling, aborting.")
                    abort()
                }
            }
        }

        //Write Schedule Data
        self.schd_task = schd_task
        return schd_task
    }

    /*
     * public func scheduleDuration() -> [SKMDuration]
     * - Merges Void Duration and Schedulable duration into an chronologically ordered Array.
     * [Return]
     * Array<SKMDuration> - Chronologically ordered Array of Void Duration and Schedulable DUration
     * [Error]
    */
    public func scheduleDuration() -> [SKMDuration]
    {
        //Obtain Data
        var arr_voidd = self.dataCtrl.sortedVoidDuration(sattr: SKMVoidDurationSort.begin) //Void Duration
        var arr_schdd = self.generateSchedulableDuration() //Schedulable Duration

        //Result Data
        var arr_drsn =  Array<SKMDuration>()

        //Merge Duration
        while arr_voidd.count > 0 && arr_schdd.count > 0
        {
            if arr_voidd[0].begin.compare((arr_schdd[0].begin as Date)) == ComparisonResult.orderedAscending
            {
                //Current Void Duration begin date < Current Schedulable Duration Date
                let crt_voidd = arr_voidd.removeFirst()
                arr_drsn.append((crt_voidd as SKMDuration))
            }
            else
            {
                //Current Void Duration begin date >= Current Scvhedule Duration Date
                let crt_schdd = arr_schdd.removeFirst()
                arr_drsn.append(crt_schdd)
            }
        }

        if arr_voidd.count > 0
        {
            //Append Remainding Void Duration
            arr_drsn.append(contentsOf:(arr_voidd as [SKMDuration]))
        }
        else if arr_schdd.count > 0
        {
            //Append Remainding
            arr_drsn.append(contentsOf: arr_schdd)
        }

        //Save Data
        self.schd_drsn = arr_drsn
        
        return arr_drsn
    }
    
    /*
     * public func randomSchedule
     * - Shuffles the current schedule randomly
    */
    public func randomSchedule()
    {
        //Prepare Random Number Generate Data
        for (drsn,arr_stsk) in self.schd_task
        {
            var arr_tgt = arr_stsk //To Avoid arr_stsk constant error

            //Randomly Shuffle Subtasks
            for i in (0..<arr_tgt.count).reversed()
            {
                //Generate Random Num < i
                let rn = Int(arc4random_uniform(UInt32(i)))
                //Swap Values
                let val1 = arr_tgt[i]
                arr_tgt[i] = arr_tgt[rn]
                arr_tgt[rn] = val1
            }

            self.schd_task[drsn] = arr_stsk
        }
    }
}
