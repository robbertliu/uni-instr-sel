/**
 * Copyright (c) 2014, Gabriel Hjort Blindell <ghb@kth.se>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

#include "constraints.h"
#include "../exceptions/exception.h"

using namespace Model;

Constraint::Constraint(BoolExpr* expr)
    : expr_(expr)
{
    if (!expr_) THROW(Exception, "expr cannot be NULL");
}

Constraint::~Constraint(void) {
    delete expr_;
}

BoolExpr*
Constraint::getExpr(void) const {
    return expr_;
}

Expr::Expr(void) {}

Expr::~Expr(void) {}

BoolExpr::BoolExpr(void) {}

BoolExpr::~BoolExpr(void) {}

NumExpr::NumExpr(void) {}

NumExpr::~NumExpr(void) {}

NodeIdExpr::NodeIdExpr(void) {}

NodeIdExpr::~NodeIdExpr(void) {}

InstanceIdExpr::InstanceIdExpr(void) {}

InstanceIdExpr::~InstanceIdExpr(void) {}

InstructionIdExpr::InstructionIdExpr(void) {}

InstructionIdExpr::~InstructionIdExpr(void) {}

PatternIdExpr::PatternIdExpr(void) {}

PatternIdExpr::~PatternIdExpr(void) {}

LabelIdExpr::LabelIdExpr(void) {}

LabelIdExpr::~LabelIdExpr(void) {}

RegisterIdExpr::RegisterIdExpr(void) {}

RegisterIdExpr::~RegisterIdExpr(void) {}

EqExpr::EqExpr(NumExpr* lhs, NumExpr* rhs)
    : BinaryExpr(lhs, rhs)
{}

EqExpr::~EqExpr(void) {}

NeqExpr::NeqExpr(NumExpr* lhs, NumExpr* rhs)
    : BinaryExpr(lhs, rhs)
{}

NeqExpr::~NeqExpr(void) {}

GTExpr::GTExpr(NumExpr* lhs, NumExpr* rhs)
    : BinaryExpr(lhs, rhs)
{}

GTExpr::~GTExpr(void) {}

GEExpr::GEExpr(NumExpr* lhs, NumExpr* rhs)
    : BinaryExpr(lhs, rhs)
{}

GEExpr::~GEExpr(void) {}

LTExpr::LTExpr(NumExpr* lhs, NumExpr* rhs)
    : BinaryExpr(lhs, rhs)
{}

LTExpr::~LTExpr(void) {}

LEExpr::LEExpr(NumExpr* lhs, NumExpr* rhs)
    : BinaryExpr(lhs, rhs)
{}

LEExpr::~LEExpr(void) {}

EqvExpr::EqvExpr(BoolExpr* lhs, BoolExpr* rhs)
    : BinaryExpr(lhs, rhs)
{}

EqvExpr::~EqvExpr(void) {}

ImpExpr::ImpExpr(BoolExpr* lhs, BoolExpr* rhs)
    : BinaryExpr(lhs, rhs)
{}

ImpExpr::~ImpExpr(void) {}

AndExpr::AndExpr(BoolExpr* lhs, BoolExpr* rhs)
    : BinaryExpr(lhs, rhs)
{}

AndExpr::~AndExpr(void) {}

OrExpr::OrExpr(BoolExpr* lhs, BoolExpr* rhs)
    : BinaryExpr(lhs, rhs)
{}

OrExpr::~OrExpr(void) {}

NotExpr::NotExpr(BoolExpr* expr)
    : UnaryExpr(expr)
{}

NotExpr::~NotExpr(void) {}

PlusExpr::PlusExpr(NumExpr* lhs, NumExpr* rhs)
    : BinaryExpr(lhs, rhs)
{}

PlusExpr::~PlusExpr(void) {}

MinusExpr::MinusExpr(NumExpr* lhs, NumExpr* rhs)
    : BinaryExpr(lhs, rhs)
{}

MinusExpr::~MinusExpr(void) {}

AnIntegerExpr::AnIntegerExpr(int i)
    : i_(i)
{}

AnIntegerExpr::~AnIntegerExpr(void) {}

int
AnIntegerExpr::getValue(void) const {
    return i_;
}

NodeIdToNumExpr::NodeIdToNumExpr(NodeIdExpr* expr)
    : UnaryExpr(expr)
{}

NodeIdToNumExpr::~NodeIdToNumExpr(void) {}

InstanceIdToNumExpr::InstanceIdToNumExpr(InstanceIdExpr* expr)
    : UnaryExpr(expr)
{}

InstanceIdToNumExpr::~InstanceIdToNumExpr(void) {}

InstructionIdToNumExpr::InstructionIdToNumExpr(InstructionIdExpr* expr)
    : UnaryExpr(expr)
{}

InstructionIdToNumExpr::~InstructionIdToNumExpr(void) {}

PatternIdToNumExpr::PatternIdToNumExpr(PatternIdExpr* expr)
    : UnaryExpr(expr)
{}

PatternIdToNumExpr::~PatternIdToNumExpr(void) {}

LabelIdToNumExpr::LabelIdToNumExpr(LabelIdExpr* expr)
    : UnaryExpr(expr)
{}

LabelIdToNumExpr::~LabelIdToNumExpr(void) {}

RegisterIdToNumExpr::RegisterIdToNumExpr(RegisterIdExpr* expr)
    : UnaryExpr(expr)
{}

RegisterIdToNumExpr::~RegisterIdToNumExpr(void) {}

ANodeIdExpr::ANodeIdExpr(const Id& id)
    : id_(id)
{}

ANodeIdExpr::~ANodeIdExpr(void) {}

Id
ANodeIdExpr::getId(void) const {
    return id_;
}

AnInstanceIdExpr::AnInstanceIdExpr(const Id& id)
    : id_(id)
{}

AnInstanceIdExpr::~AnInstanceIdExpr(void) {}

Id
AnInstanceIdExpr::getId(void) const {
    return id_;
}

AnInstructionIdExpr::AnInstructionIdExpr(const Id& id)
    : id_(id)
{}

AnInstructionIdExpr::~AnInstructionIdExpr(void) {}

Id
AnInstructionIdExpr::getId(void) const {
    return id_;
}

APatternIdExpr::APatternIdExpr(const Id& id)
    : id_(id)
{}

APatternIdExpr::~APatternIdExpr(void) {}

Id
APatternIdExpr::getId(void) const {
    return id_;
}

ALabelIdExpr::ALabelIdExpr(const Id& id)
    : id_(id)
{}

ALabelIdExpr::~ALabelIdExpr(void) {}

Id
ALabelIdExpr::getId(void) const {
    return id_;
}

ARegisterIdExpr::ARegisterIdExpr(const Id& id)
    : id_(id)
{}

ARegisterIdExpr::~ARegisterIdExpr(void) {}

Id
ARegisterIdExpr::getId(void) const {
    return id_;
}

ThisInstanceIdExpr::ThisInstanceIdExpr(void) {}

ThisInstanceIdExpr::~ThisInstanceIdExpr(void) {}

CovererOfActionNodeExpr::CovererOfActionNodeExpr(NodeIdExpr* expr)
    : UnaryExpr(expr)
{}

CovererOfActionNodeExpr::~CovererOfActionNodeExpr(void) {}

DefinerOfEntityNodeExpr::DefinerOfEntityNodeExpr(NodeIdExpr* expr)
    : UnaryExpr(expr)
{}

DefinerOfEntityNodeExpr::~DefinerOfEntityNodeExpr(void) {}

InstructionIdOfPatternExpr::InstructionIdOfPatternExpr(PatternIdExpr* expr)
    : UnaryExpr(expr)
{}

InstructionIdOfPatternExpr::~InstructionIdOfPatternExpr(void) {}

PatternIdOfInstanceExpr::PatternIdOfInstanceExpr(InstanceIdExpr* expr)
    : UnaryExpr(expr)
{}

PatternIdOfInstanceExpr::~PatternIdOfInstanceExpr(void) {}

LabelIdAllocatedToInstanceExpr::LabelIdAllocatedToInstanceExpr(
    InstanceIdExpr* expr
)
    : UnaryExpr(expr)
{}

LabelIdAllocatedToInstanceExpr::~LabelIdAllocatedToInstanceExpr(void) {}

LabelIdOfLabelNodeExpr::LabelIdOfLabelNodeExpr(NodeIdExpr* expr)
    : UnaryExpr(expr)
{}

LabelIdOfLabelNodeExpr::~LabelIdOfLabelNodeExpr(void) {}

RegisterIdAllocatedToDataNodeExpr::RegisterIdAllocatedToDataNodeExpr(
    NodeIdExpr* expr
)
    : UnaryExpr(expr)
{}

RegisterIdAllocatedToDataNodeExpr::~RegisterIdAllocatedToDataNodeExpr(void) {}
