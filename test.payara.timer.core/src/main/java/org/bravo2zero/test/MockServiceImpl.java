package org.bravo2zero.test;

import javax.ejb.Stateless;

@Stateless
public class MockServiceImpl implements MockService {


	public void mockTask() {
		System.out.println("Mock task called");
	}
}
