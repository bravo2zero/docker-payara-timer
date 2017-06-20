package org.bravo2zero.test;


import javax.ejb.*;

@Stateless
public class TimerSchedule {

	@EJB
	private MockService service;

	@Schedule(hour = "*", minute = "*/1")
	public void mockTimer() {
		System.out.println("execute test timer");
		service.mockTask();
	}}
