
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("StakingContract Test", function () {
    
  it("StakingContract Test starts", async function () {
    
    const [owner, addr1, addr2, bountyWallet] = await ethers.getSigners();
    const Topbot = await ethers.getContractFactory("Topbot");
    const topbot = await Topbot.deploy("TopbotToken", "Topbot", ethers.utils.parseUnits('100000000000', 'ether'));
    const tokenAddress = topbot.address;
    
    const bountyValue = ethers.utils.parseUnits('100000000', 'ether');
    
    await topbot.transfer(bountyWallet.address, bountyValue);
    await topbot.transfer(addr1.address, bountyValue);

    const getbalance = async(address) => {

      let balance = await topbot.balanceOf(address);
      return balance;
    }
    
    const StakingContract = await ethers.getContractFactory("StakingPlatform");
    const stakingContract = await StakingContract.deploy(topbot.address); 

    const stakeAmount = ethers.utils.parseUnits('10000000', 'ether');

    let b = await getbalance(addr1.address);

    console.log(b);
    
    await topbot.connect(addr1).approve(stakingContract.address, stakeAmount);
    await stakingContract.connect(addr1).startStaking(stakeAmount, 0);
    await topbot.connect(addr1).approve(stakingContract.address, stakeAmount);
    await stakingContract.connect(addr1).stake(stakeAmount);
    
    let stakedamount = await stakingContract.connect(addr1).stakedAmount(addr1.address);
    
    console.log(stakedamount);
    
    await stakingContract.connect(addr1).withdraw(stakeAmount);
    
    stakedamount = await stakingContract.connect(addr1).stakedAmount(addr1.address);
    
    console.log(stakedamount);
  });
  
});